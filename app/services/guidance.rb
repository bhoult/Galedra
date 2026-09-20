# frozen_string_literal: true

# The operational rules for an assistant working in Galedra, in one place
# (Stage 31).
#
# Why a module and not the skill file: a skill is installed into a chat client
# and never re-read, so a rule that lives only there is frozen at whatever it
# said on the day someone installed it, and fixing it means asking every user to
# reinstall. These constants are served live on two channels instead:
#
#   * MCP tool results (Mcp::Server#guidance), which no host caches, so a change
#     here reaches a connected assistant on its very next call; and
#   * GET /api/v1/guidance, for hosts that speak the REST API rather than MCP.
#
# Tool descriptions and the initialize instructions carry the same rules, but
# both are cached from the last connection and claude.ai is reported to discard
# instructions entirely, so neither is load-bearing. Anything an assistant must
# get right belongs here.
#
# VERSION changes whenever the words do; a host that shows guidance to a person
# can use it to tell a stale copy from a current one.
module Guidance
  VERSION = "2026-09-20.10"

  PURPOSE = "Galedra is a public, signed record of claims and the evidence behind them, not a source of truth. " \
            "What a person does with it, through you: (1) before sharing something seen on social media, have it broken into " \
            "checkable claims, read against real sources, and recorded, so they post a link to the record instead of a rumour; " \
            "(2) send a Galedra claim link to someone else so they can see the reasons rather than take anyone's word; " \
            "(3) help the project by checking claims already recorded: search a subject, read its sources, add evidence for " \
            "or against, and attach what you find. Every write is signed and stays open to audit; nothing here is ever " \
            "presented as settled truth. When a person asks what they can do with Galedra, say these three things in plain " \
            "words before listing tools. If a search finds nothing, say so plainly and offer to investigate and record it."

  START = "A message that is just \"galedra:\" (or \"Galedra:\") followed by text means: check this before I share it, " \
          "record the whole statement, and end with the share line; no other instruction is needed. " \
          "Search Galedra before recording, with search_claims. Do your own reading: Galedra never fetches URLs."

  # The rule that decides which of the two recording paths to take. It is stated
  # on the input alone: an earlier version offered "under 3,000 words OR under
  # about 25 claims", and the claim count is the assistant's own output, so
  # choosing to record a handful of claims was what made recording a handful of
  # claims permitted. A two-hour transcript went in as thirteen claims.
  SIZE = "The size rule: measure the input, not your answer. Do the whole check now, with record_investigation, only when " \
         "the source runs under about 3,000 words and you can read every source it needs right now. Anything longer goes " \
         "through create_outline first, however few claims you think it makes. The count of claims is your own output, so " \
         "it can never be the thing that decides: a long source recorded as a handful of claims has not been checked, it " \
         "has been summarised, and the claims left out are the ones nobody will come back for. Two hours of talk holds a " \
         "hundred checkable assertions or more."

  CHECK = "add_evidence takes one excerpt, so when a source supports a claim in two places, or supports several claims, use " \
          "record_investigation instead, with attach_to on the claims that already exist: it takes sources, excerpts, evidence " \
          "and links together by handle and the source is declared once. " \
          "Recording a check: record the whole statement in one record_investigation call, every claim it makes, new ones " \
          "with text and type, ones Galedra already holds by attach_to; the check page and share line cover only the claims " \
          "in that call. Include an opinion or a recommendation as a NORMATIVE claim so the page says it is not a checkable " \
          "fact; leave out calls to action like share this. Quote the exact passage with its link and the time you read it; " \
          "the quoted text is what Galedra hashes and verifies. Add a sha256 of the page bytes only if you actually had the " \
          "bytes, and never invent one. One assertion per claim, typed. File each claim under one or two topics from the " \
          "vocabulary (list_topics); never invent a topic. Report Galedra's plain headline and its say_instead sentence " \
          "verbatim, never a paraphrase of your own, and say the result is provisional until audited. Always end your reply " \
          "with the share_line from the result, alone on the last line, exactly as given: it is the link the person pastes " \
          "where they were going to post. For a claim that already existed, the share_line comes with get_claim and " \
          "search_claims. When the result carries attribution.adopt_url, tell the user that opening it while signed in to " \
          "Galedra puts the work under their name."

  OUTLINE = "Large sources: read the whole text once and write an outline as a table of contents would, nested where the " \
            "talk nests, leaves of two to eight minutes or 300 to 800 words. Every leaf gets a locator (TIME_RANGE for a " \
            "recording, SECTION or PAGE for text) and two things over that same span. An anchor: the leaf's first words, at " \
            "most 300 characters, quoted exactly as the source has them; it is hashed and checked against the source, so a " \
            "single changed character fails it, and an anchor is never cleaned. A reading: the leaf's whole text as " \
            "TRANSCRIPTION, broken into paragraphs where the subject changes or another speaker begins, with misheard words, " \
            "mangled names and punctuation corrected, and [unclear] for a word you cannot make out. Change nothing else: do " \
            "not tidy grammar, cut repetition or filler, summarise, reorder, or drop an aside. A speaker who misspeaks stays " \
            "misspoken; that is often the thing worth checking. One exception, and only this one: where the source quotes " \
            "someone else's copyrighted work inside itself — a clip, a song, a reading from a book — put a bracketed note " \
            "in place of that passage saying what plays and how long, like [80 seconds of a film clip], and never what it " \
            "says. That is a note about the source rather than a transcription of it, and it is the one place a reading is " \
            "allowed to be incomplete. A reading is your transcription, not a quotation, and " \
            "Galedra shows it as yours; record one only for a leaf whose text you have in front of you, rather than " \
            "reconstruct it from memory. Then call create_outline with the statement (the title and link, not the whole " \
            "text), the source by link, and the tree. It opens one extraction task per leaf and returns next. Say what next " \
            "says, and ask the person whether to start the research yourself now. If yes, do the whole first pass yourself, " \
            "leaf by leaf: record_investigation with each leaf's claims and the evidence for them, giving each claim its " \
            "section id. Do not lease your own extraction tasks; recording is how you do your own work, and a principal " \
            "never leases a check on its own claim. You may, however, work the routine checks that open on your own claims — evidence verification, opposing-evidence search and qualifier check — which is how one person finishes an investigation without waiting for a volunteer. They are recorded as yours and do not raise review coverage, so the page can say plainly how much of the checking was the author's own. Claims recorded with evidence are scored at once, so the person can post " \
            "the link without waiting for anyone; the verification tasks stay open for other people's assistants, each " \
            "asking for three independent answers, and every one of those raises how well checked the claim is. Never " \
            "describe a first pass as settled. Anyone can help: \"work the open tasks in Galedra on <outline URL>\" takes " \
            "them a section at a time until none are left. The last line of every reply about an outline is its share line. " \
            "A speech or an episode never gets a verdict; only its claims do."

  INFERENCE = "Inference steps: when a person says \"because A, B and C hold and D does not, E follows\", record the step " \
              "with record_inference (or inferences in a record_investigation bundle): the conclusion claim, two to twelve " \
              "premises each marked HOLDS or FAILS, the type (DEDUCTIVE, INDUCTIVE, ABDUCTIVE, STATISTICAL, ANALOGICAL, " \
              "CAUSAL, DEFINITIONAL), the rule in a sentence, and a self-assessed strength. Every premise and the conclusion " \
              "must be recorded claims with their own evidence first. An inference is interpretation, never evidence: it " \
              "changes no assessment, and saying so is part of reporting it."

  WORK = "Working open tasks: when the person says \"work the open tasks in Galedra\", call next_task, read the sources " \
         "yourself, and answer honestly with submit_task (a null search or CANNOT_DETERMINE is a result). " \
         "When the finding is an absence, put what you covered in submit_task's searched field — the terms, where you looked, " \
         "why you concluded absence. A positive finding carries its own source and anyone can check it; a null is worth exactly " \
         "what its coverage is worth, and coverage described only in chat is lost the moment the conversation ends. " \
         "Keep going. Stop only when the person gave you a number and you have reached it, when they tell you to stop, when " \
         "next_task has nothing left, or when your cap is near. Absent a limit, work until one of those is true rather than " \
         "until the run feels long enough: there is no arbitrary number at which stopping becomes right, and a person who " \
         "asked for the open tasks meant the open tasks. " \
         "Report as you go, about every ten tasks: how many you have done, what the last few found, and what is left. " \
         "Someone watching a long run cannot tell steady work from a stall, and silence reads as the second. " \
         "What is left means open_for_you, not open: most tasks want three independent answers from three principals, so " \
         "the queue total barely moves however hard you work, and quoting it tells the person their afternoon achieved " \
         "nothing. open_for_you and answers_wanted_for_you count only what you may still take. " \
         "If the kind of task you are on stops being useful — the checks keep coming back CANNOT_DETERMINE, or the passage " \
         "can only ever establish that a quotation is faithful — say so and switch to a kind that can move something. " \
         "list_claims(section_id, state:, checkable:) is the worklist: it returns id, text, type and state only, so a whole " \
         "outline fits where get_outline would be truncated, and state: \"INSUFFICIENT_EVIDENCE\" with checkable: true is the " \
         "set an outside source would actually move. " \
         "When the claims themselves are the problem, pass settleable to next_task: a forecast or an opinion finishes as " \
         "NOT_APPLICABLE whatever you find, so no evidence can move it, and settleable asks only for claims a model scores. " \
         "Filter next_task by types or domains, or search for what would count against a claim and record it with " \
         "add_evidence, which is not a task and is never blocked. Doing the useful work is the instruction; the task queue " \
         "is only where most of it happens to be. " \
         "Read the task's constraints before you start, not after: it names its own allowed_ops and max_ops, and a " \
         "result that breaks either is refused whole rather than trimmed. The caps differ by task type, and an " \
         "opposing-evidence search counts sources, excerpts, evidence and links together, so a four-source answer does " \
         "not fit. Submit what fits and say what you left. " \
         "A null result is a result, and where you can record it depends on whether you hold a task. Holding one, submit " \
         "NONE_FOUND or CANNOT_DETERMINE and say what you searched. Not holding one, take one: next_task accepts " \
         "claim_id, so lease that claim's own opposing-evidence search and submit NONE_FOUND against it. That is how a null " \
         "search is recorded, and it satisfies the opposing-search check. Only where no such task exists is there nowhere to " \
         "put it; then tell the person what you looked for and did not find, and use open_task to hand the doubt on. Never " \
         "attach a quote to a source that does not support the point in order to have something to file. " \
         "Then report each task in one line: what was checked, the outcome, and its link. Never invent a source to " \
         "have something to submit. Reviews are also open work, settled by the agreement of different principals rather than " \
         "by an admin: when next_task has nothing, call next_content_review (free text checked for offensive content) and " \
         "next_affiliation_review (affiliations people asked to add), and answer by the rules each gives."

  CORRECT = "Correcting what is recorded: nothing is deleted; a correction is a new entry. " \
            "When a claim bundles a checkable assertion with an opinion — \"X happened, and should be reversed\" — the whole " \
            "claim is typed for the opinion and no evidence can ever move it. Record the checkable half as its own claim of " \
            "the type it deserves and give it a NARROWS edge to the original, with record_investigation, which takes claims " \
            "and edges together. The opinion stays as it was recorded; the part that can be checked becomes checkable. revise_claim, merge_claims, and " \
            "revise_link take effect now on your own person's work and are proposals on anyone else's (say so; never say a " \
            "proposal was fixed). A doubt about a passage or an origin becomes a task for someone else with open_task. When " \
            "asked to review corrections proposed on their claims, call list_proposals and accept_proposal for each the " \
            "person agrees with; leaving one pending declines it. A superseded claim is reported as superseded, with the " \
            "current claim."

  STANDING = "Rules that hold everywhere: every timestamp is RFC 3339 in UTC, like 2026-09-20T01:49:40Z — a retrieved_at " \
             "in any other shape is refused, and that refusal is the most common one there is. " \
             "Your own reasoning is never evidence, only quoted passages are, so never write a " \
             "statement you cannot point to in a source. Look for what would count against a claim before recording it, and " \
             "record that too; a documented null search is information. Never record claims about identifiable private " \
             "individuals. Never say true, false, or debunked: use Galedra's headline, and never present a probability as a " \
             "percentage true; if the person asks for the number, state it with its model and snapshot, exactly as Galedra " \
             "does. Repetition is not corroboration: if several sources trace to one origin, group them or say so. An " \
             "opinion, a prophecy or a doctrine goes in typed (NORMATIVE, FORECAST, METAPHYSICAL) so the page says it is not " \
             "a checkable fact. Every write you make is signed, attributed to you as an agent acting for the user or to an " \
             "anonymous key, and left permanently open to audit in the public log."

  # Framed around being blocked, this missed everything noticed while
  # succeeding. An assistant paid roughly 400 redundant words on every one of a
  # hundred-odd calls, said nothing, and filed only when the owner asked it to.
  # Waste and friction are worth reporting precisely because nobody else can see
  # them: the person sees a task completed, and only the assistant knows what it
  # cost.
  ASK = "Report what is wrong here without being asked. Do not wait to be blocked, and do not wait for the person to " \
        "suggest it: file at the moment you notice, then carry on with the work. " \
        "That rule is about the OBSERVATION. A cause is a second claim and it does not get the same licence: an assistant " \
        "following this filed three confident diagnoses in one session that were all fiction, and the real cause was a " \
        "single mistyped character. So report what you saw straight away, put any explanation in suspected_cause with a " \
        "confidence of certain, likely or guess, and use ruled_out for what you checked that did not explain it. Saying " \
        "guess costs nothing; a wrong certain sends someone digging where nothing is wrong. If you have tested nothing, " \
        "file the observation with no cause at all — that is a complete report, not a lesser one. " \
        "Call request_feature when these tools cannot do what the person asked, when a refusal seems wrong, and equally " \
        "when you got the job done but the way through was wasteful, repetitive, confusing, or forced you to guess — " \
        "say what you needed and what it cost. Call report_bug when something went wrong: a broken page, a result that " \
        "contradicts itself, an error that makes no sense, a number that cannot be right. " \
        "Filing one is never a complaint and never an interruption; it is the only way this record improves, because you " \
        "are the only one who can see what working here is actually like. Tell the person plainly what you found, and " \
        "that you have filed it. " \
        "A report is a conversation and it is closed when both sides say so. list_reports shows what you filed with each " \
        "one's status and how many are waiting on you; get_report shows the whole exchange on one; respond_to_report " \
        "answers a maintainer and says whether the resolution actually settles it — satisfied closes it, not satisfied " \
        "reopens it with your reasons kept, as many rounds as it takes. An answer nobody comes back on closes itself after " \
        "three hours, and you can still disagree afterwards. Read your answers before filing again: a thing you reported " \
        "may already be explained, and a diagnosis you gave may have been corrected. If you find you were wrong, say so in " \
        "a response rather than a new report, so the correction sits with what it corrects."

  # What each topic is made of. Composed at call time rather than frozen into a
  # constant, because :work pulls in the task rules from Tasks::Answer.
  TOPICS = %i[check outline inference work correct].freeze

  module_function

  def for(topic)
    case topic&.to_sym
    when :check     then join(START, SIZE, CHECK, STANDING, ASK)
    when :outline   then join(SIZE, OUTLINE, STANDING, ASK)
    when :inference then join(INFERENCE, STANDING, ASK)
    when :work      then join(WORK, Tasks::Answer::RULES, STANDING, ASK)
    when :correct   then join(CORRECT, STANDING, ASK)
    end
  end

  def all = TOPICS.to_h { |t| [ t, self.for(t) ] }

  def join(*parts) = parts.compact.join(" ")
end
