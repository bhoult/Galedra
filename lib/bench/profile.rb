# frozen_string_literal: true

module Bench
  # CPU and memory profiling of the workloads bench:report times (Stage 26).
  #
  # Development only. The gems are in the development bundle group and the
  # production image installs with BUNDLE_WITHOUT=development, so none of this
  # can load there; each mode requires its gem at the moment it runs rather
  # than at boot.
  #
  # Three questions, three modes:
  #   cpu     where the time goes inside one operation
  #   memory  what allocates, and what is still held afterwards
  #   rss     whether the process grows as it serves, and how big it gets
  class Profile
    DIR = Rails.root.join("tmp/profile")
    DEFAULT_ITERATIONS = 20
    DEFAULT_RSS_ITERATIONS = 100

    class << self
      # A sampling profile. Wall mode by default: on these pages the question
      # is where the time goes, and much of it is spent waiting on Postgres,
      # which CPU mode cannot see. MODE=cpu for on-processor time only.
      def cpu(query, iterations: DEFAULT_ITERATIONS, mode: :wall, cold: true, out: $stdout)
        require "stackprof"
        found = resolve(query, out)
        return if found.nil?

        name, work = found

        warm(work)
        result = Isolation.call(cold: cold) do
          StackProf.run(mode: mode, interval: mode == :wall ? 1_000 : 200, raw: false) do
            iterations.times { work.call }
          end
        end
        # Written here rather than through StackProf's own out:, which returns
        # the file instead of the result. The CLI reads a Marshal dump.
        path = path_for("cpu", name, mode)
        path.binwrite(Marshal.dump(result))
        print_frames(name, mode, iterations, result, path, cold, out)
      end

      # What one run allocates, and what it leaves behind. Warmed first, so
      # one-time loading does not drown the work itself.
      def memory(query, cold: true, out: $stdout)
        require "memory_profiler"
        found = resolve(query, out)
        return if found.nil?

        name, work = found

        warm(work)
        report = Isolation.call(cold: cold) { MemoryProfiler.report { work.call } }
        path = path_for("memory", name)
        report.pretty_print(to_file: path.to_s, scale_bytes: true, detailed_report: true)
        print_memory(name, report, path, cold, out)
      end

      # Does the process grow as it serves? Reports resident set after boot,
      # after a warm run, and across iterations, with the slope. Growth that
      # survives a full GC is the number that decides the box size.
      def rss(query, iterations: DEFAULT_RSS_ITERATIONS, cold: true, out: $stdout)
        found = resolve(query, out)
        return if found.nil?

        name, work = found

        out.printf("%-28s %s\n", "resident set at start", human(rss_kb))
        warm(work)
        GC.start
        base = rss_kb
        samples = Isolation.call(cold: cold) { Array.new(iterations) { work.call; rss_kb } }
        GC.start
        settled = rss_kb

        # A Ruby process grows while its heap settles and never hands the
        # pages back, so growth measured from the first run always looks like
        # a leak. The slope over the second half is the honest number.
        half = iterations / 2
        midpoint = samples[half - 1] || base
        # From the samples, not from the post-GC reading: a full GC moves the
        # resident set by a little in either direction and is not a trend.
        per_run = (samples.last - midpoint) / (iterations - half).to_f

        out.printf("%-28s %s\n", "after one warm run", human(base))
        out.printf("%-28s %s\n", "halfway, after #{half} runs", human(midpoint))
        out.printf("%-28s %s\n", "after #{iterations} runs", human(samples.last))
        out.printf("%-28s %s\n", "after a full GC", human(settled))
        out.printf("%-28s %s\n", "peak", human(samples.max))
        out.printf("%-28s %s per run\n", "steady-state slope", human(per_run))
        out.puts
        out.puts "#{name}: #{verdict(per_run)}"
        out.puts gc_line
        out.puts Isolation.note
      end

      # Boot cost alone: what the process holds having loaded the application
      # and served nothing.
      def boot(out: $stdout)
        GC.start
        out.puts "resident set after boot, having served nothing: #{human(rss_kb)}"
        out.puts gc_line
        out.puts "ruby #{RUBY_VERSION}, #{Rails.env}, #{Etc.nprocessors} cpu"
      end

      private

      def resolve(query, out)
        name, work = Workloads.find(query)
        return [ name, work ] if work

        out.puts "No workload matches #{query.inspect}. Available:"
        Workloads.names.each { |n| out.puts "  #{n}" }
        nil
      end

      # One untimed run, so class loading, query plans and the score cache are
      # not what the profile shows.
      def warm(work)
        Isolation.call { work.call }
      rescue StandardError => e
        warn "warm-up raised #{e.class}: #{e.message}"
      end

      def path_for(kind, name, suffix = nil)
        FileUtils.mkdir_p(DIR)
        slug = name.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
        DIR.join([ kind, slug, suffix ].compact.join("-") + (kind == "cpu" ? ".dump" : ".txt"))
      end

      def print_frames(name, mode, iterations, result, path, cold, out)
        total = result[:samples].to_i
        out.puts "#{name}: #{iterations} runs, #{total} samples, #{mode} mode"
        out.puts
        out.printf("%7s %7s  %s\n", "self", "total", "frame")
        frames = result[:frames].values.sort_by { |f| -f[:samples].to_i }
        frames.first(25).each do |f|
          out.printf("%6.1f%% %6.1f%%  %s\n", pct(f[:samples], total), pct(f[:total_samples], total), f[:name].to_s[0, 78])
        end
        out.puts
        out.puts Isolation.note(cold: cold)
        out.puts "dump: #{path}"
        out.puts "read it with: bundle exec stackprof #{path} --text --limit 40"
        out.puts "              bundle exec stackprof #{path} --method '<Class>#<method>'"
      end

      def print_memory(name, report, path, cold, out)
        out.puts "#{name}: one run after warm-up"
        out.puts
        out.printf("%-12s %12s %10s\n", "", "bytes", "objects")
        out.printf("%-12s %12s %10d\n", "allocated", human(report.total_allocated_memsize / 1024.0), report.total_allocated)
        out.printf("%-12s %12s %10d\n", "retained", human(report.total_retained_memsize / 1024.0), report.total_retained)
        out.puts
        out.puts "allocated bytes by file"
        by_file(report.allocated_memory_by_file, out)
        out.puts
        out.puts "retained bytes by file (what the run leaves behind)"
        report.retained_memory_by_file.any? ? by_file(report.retained_memory_by_file, out) : out.puts("  nothing retained")
        out.puts
        out.puts Isolation.note(cold: cold)
        out.puts "full report: #{path}"
      end

      # memory_profiler hands back {data: <file>, count: <bytes>} rows.
      def by_file(rows, out)
        rows.first(12).each { |row| out.printf("  %10s  %s\n", human(row[:count] / 1024.0), relative(row[:data])) }
      end

      # Resident set in KB. /proc is the honest number inside a container:
      # GC.stat reports the Ruby heap, not what the kernel has handed out.
      def rss_kb
        File.read("/proc/self/status")[/VmRSS:\s+(\d+) kB/, 1].to_i
      rescue Errno::ENOENT
        `ps -o rss= -p #{Process.pid}`.to_i
      end

      # Below a kilobyte a run is indistinguishable from heap noise at these
      # sample sizes; anything that holds a steady slope is worth chasing.
      def verdict(per_run)
        return "flat once the heap settles; nothing accumulates" if per_run <= 4

        "still growing #{human(per_run)} a run once the heap has settled, which is #{human(per_run * 1000)} per thousand requests"
      end

      def gc_line
        s = GC.stat
        "ruby heap #{human(s[:heap_live_slots] * 40 / 1024.0)} live, #{s[:major_gc_count]} major and #{s[:minor_gc_count]} minor collections"
      end

      def pct(part, whole) = whole.to_i.zero? ? 0.0 : (part.to_f / whole) * 100
      def relative(file) = file.to_s.sub(Rails.root.to_s + "/", "").sub(%r{\A/usr/local/bundle/(?:ruby/[^/]+/)?gems/}, "gem:")

      def human(kb)
        return format("%.0f KB", kb) if kb < 1024

        kb < 1024 * 1024 ? format("%.1f MB", kb / 1024.0) : format("%.2f GB", kb / 1024.0 / 1024)
      end
    end
  end
end
