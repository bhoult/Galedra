module ApplicationHelper
  # The content column of an outline page. Named once, so the page, the tree
  # and every link into it agree. A method rather than a constant, because a
  # view cannot reach a helper's constants by bare name.
  OUTLINE_FRAME = "outline-content"

  def outline_frame = OUTLINE_FRAME

  # A navigation link, with an optional definition of the term it names. Only
  # words that mean something particular here get one: "claim", "audit" and
  # "outline" are not what a reader would assume from ordinary usage, while
  # "users" and "bug reports" are. Explaining the obvious trains people to
  # ignore the explanations.
  #
  # The text is carried as data-tip, which the tooltip controller shows after a
  # second's hover, and as title, which the browser shows when JavaScript is
  # not running. The controller removes the title when it takes over.
  def nav_link(label, path, tip = nil)
    return link_to(label, path) if tip.blank?

    link_to label, path, title: tip, data: { tip: tip }
  end

  # What is waiting on a maintainer, in the bar an admin is already looking at
  # (owner request, 2026-09-20). OPEN only: ANSWERED is the filer's turn, and a
  # held report is waiting on work already planned, so neither is something to
  # act on now. Counting those would make the badge a number nobody can clear.
  #
  # Memoised per request because the header renders on every page.
  # What a thread hangs on, in words a reader would recognise rather than an id.
  def thread_subject_label(thread)
    row = thread.subject
    case row
    when Claim then truncate(row.canonical_text.to_s.squish, length: 70)
    when EvidenceClaimLink then "a link on #{truncate(row.claim&.canonical_text.to_s.squish, length: 50)}"
    when EvidenceItem then "evidence: #{truncate(row.statement.to_s.squish, length: 55)}"
    when SourceLocation then "a quoted passage: #{truncate(row.excerpt.to_s.squish, length: 50)}"
    when TaskAssignment then "a task result"
    else "#{thread.subject_type.underscore.humanize.downcase} (no longer here)"
    end
  end

  def thread_subject_path(thread)
    row = thread.subject
    case row
    when Claim then claim_path(row)
    when EvidenceClaimLink then claim_path(row.claim_id)
    when EvidenceItem then evidence_path(row)
    when SourceLocation then source_path(row.source_id)
    else thread_path(thread)
    end
  end

  def open_report_counts
    @open_report_counts ||= { bugs: BugReport.where(status: "OPEN").count, features: FeatureRequest.where(status: "OPEN").count,
                              held_bugs: BugReport.held.count, held_features: FeatureRequest.held.count,
                              # Threads that can still be moved along. A thread on a claim that
                              # is no longer current is history rather than work, and that is
                              # expressible in SQL — the header renders on every page including
                              # the signed-out home page, so it must not walk every thread and
                              # query each one's subject.
                              threads: DeterminationThread.workable.count }
  end
end
