# Code comments: a sourced reference for a near-zero-comment policy

Scope: when is a comment justified in C# or shell source, under a policy whose
target is close to zero comment lines. Rule of thumb the policy encodes: **a
comment is allowed only if it states something a reader cannot derive from the
code itself, its names, its tests, or the project's documentation.** This
document sources that rule against the field's main authorities, gives a
taxonomy with verdicts, a mechanical pre-write test, evidence on comment rot,
current lint enforcement, and a recommended allowed-class list a hook can
pattern-match.

---

## 1. The authorities, and where they disagree

### Robert C. Martin, *Clean Code* (Prentice Hall, 2008), ch. 4 "Comments"
Position: comments are an admission of failure to express intent in code;
every comment is a lie waiting to happen because it can drift from the code it
describes while the code silently changes underneath it.

> "The proper use of comments is to compensate for our failure to express
> ourself in code. Note that I used the word failure. I meant it. Comments are
> always failures." — ch. 4, opening.
Sample chapter: https://ptgmedia.pearsoncmg.com/images/9780132350884/samplepages/9780132350884.pdf

Martin still lists "good" comments — legal notices, informative comments (e.g.
explaining a regex), explanation of intent, clarification of an opaque
third-party return value, warning of consequences, `TODO`, amplification —
but frames all as damage control, not a feature to reach for; Javadoc on
public APIs is an exception forced by convention, not a virtue in itself.
Secondary summaries with page-anchored excerpts:
https://vivekkhatri.com/chapter-4-comments-clean-code-robert-c-martin/ ,
https://bugzmanov.github.io/cleancode-critique/chapter_4.html

### John Ousterhout, *A Philosophy of Software Design*, 2nd ed. (Yaknyam Press, 2021), ch. 12–13
Position: **explicitly rejects** the zero/near-zero-comment goal. Chapter 12 is
built around four excuses developers give for not writing comments, and the
first excuse he demolishes by name is "good code is self-documenting."

> "Some people believe that if code is written well, it is so obvious that no
> comments are needed. This is a delicious myth, like a rumor that ice cream is
> good for your health... there is still a significant amount of design
> information that can't be represented in code... If you want to use
> abstractions to hide complexity, comments are essential." — ch. 12.1.

He also rejects "comments get out of date" as grounds to minimize them —
staleness is a maintenance-discipline problem, not an argument against writing
them (ch. 12.3). Chapter 13 gives the operational content the zero-comment
policy borrows from him almost verbatim:
- **Don't repeat the code** — his test: *"could someone who has never seen the
  code write the comment just by looking at the code next to the comment? If
  the answer is yes... the comment doesn't make the code any easier to
  understand."* (ch. 13.2, "Red Flag: Comment Repeats Code.")
- **Interface vs. implementation comments** — interface comments "define the
  abstraction" (behavior, arguments, return value, side effects, exceptions,
  preconditions); implementation comments describe *what* a block does, not
  *how*, plus *why* when non-obvious (ch. 13.5, 13.8).
- **Precision vs. intuition** — lower-level comments add precision code can't
  state exactly (units, ranges, ownership); higher-level comments state intent
  at an altitude the code doesn't reach (ch. 13.3–13.4).

Book page (Stanford CS190): https://web.stanford.edu/~ouster/cgi-bin/book.php ;
text verified against the widely mirrored course PDF
https://milkov.tech/assets/psd.pdf (ch. 12–13).

**Where Martin and Ousterhout disagree, stated in two sentences each:**
- *Martin's strongest point:* a comment that merely restates working code adds
  a second copy of the truth that can rot independently of the first, so the
  default bias should be toward deleting comments and improving names instead.
  Under maintenance pressure, comments are the artifact nobody is forced to
  keep in sync, so minimizing their surface area minimizes the rot surface.
- *Ousterhout's strongest point:* a class's or method's *interface* — what
  callers may assume, what side effects exist, what the preconditions are — is
  design information that no amount of good naming can encode, because English
  prose can express constraints and rationale that a type signature cannot; without
  it, the "abstraction" is just the same complexity re-exposed to every caller.
  He treats the zero-comment position as confusing "avoid bad comments" with
  "avoid comments."

### Kevlin Henney, "Comment Only What the Code Cannot Say," in *97 Things Every Programmer Should Know*, ed. Kevlin Henney (O'Reilly, 2010)
Position: a middle path closer to Ousterhout in permission, closer to Martin in
default. The essay's title is the rule.

> "Comment what the code cannot say, not simply what it does not say." —
https://97-things-every-x-should-know.gitbooks.io/97-things-every-programmer-should-know/content/en/thing_17/

Henney's point is sharper than "explain why": a comment restating intent that
the code *could* have said (e.g. via a better name) is still forbidden, even if
the code currently doesn't say it — the fix there is to change the code, not
add the comment. Also widely quoted (talks, not a single canonical source):
"If your code needs comments, consider refactoring it so it doesn't."

### Martin Fowler and Kent Beck, *Refactoring: Improving the Design of Existing Code*, 2nd ed. (Addison-Wesley, 2018), "Comments" (in the smells catalog)
Position: comments are not inherently a smell, but are flagged in the smells
catalog because of what they are usually *used for*.

> Comments are "often used as a deodorant" — sprayed over code whose actual
> problem is that it needs restructuring, not documentation. The recommended
> refactoring is Extract Function / Rename Variable / Introduce Assertion until
> the comment becomes redundant, and only keep what's left over.
Catalog page: https://martinfowler.com/bliki/CodeSmell.html ;
canonical catalog index: https://refactoring.com/catalog/ (Fowler groups
Comments under "Dispensables" — smells whose removal, not addition, cleans the
code).

### Google style guides — C++ and Java
Position: comments are mandatory in specific, enumerated places (interfaces),
and forbidden from restating code everywhere else — the closest thing to the
policy's own target already codified by a large engineering org.

Google C++ Style Guide, "Comments" (https://google.github.io/styleguide/cppguide.html#Comments):
> "The best code is self-documenting... Giving sensible names to types and
> variables is much better than using obscure names that you must then explain
> through comments."

But under "Function Comments": *"Almost every function declaration should have
comments immediately preceding it that describe what the function does and how
to use it,"* omissible "only if the function is simple and obvious." Under
"Implementation Comments" / "Don'ts": *"Do not state the obvious... provide
higher-level comments that describe why the code does what it does, or make
the code self-describing."* Its worked example is exactly the taxonomy's
"restating the code" anti-pattern:
```
// Find the element in the vector.  <-- Bad: obvious!
if (std::find(v.begin(), v.end(), element) != v.end()) { Process(element); }
```
TODO format is standardized: `TODO` in caps + a bug ID/URL/owner + a specific
date or event, never a bare "fix this later"
(https://google.github.io/styleguide/cppguide.html#TODO_Comments).

Google Java Style Guide §7.3 "Where Javadoc is used"
(https://google.github.io/styleguide/javaguide.html#s7.3-javadoc-where-required):
Javadoc is **required** for every visible (public/protected) class, member, or
record component, with a narrow "self-explanatory members" exception (§7.3.1)
that explicitly may **not** be used to skip documenting a non-obvious term:
> "it is not appropriate to cite this exception to justify omitting relevant
> information that a typical reader might need to know."

### Microsoft C# coding conventions and .NET XML documentation comments
Microsoft's own convention page treats brief `//` comments as acceptable style
but pushes essentially all durable documentation into `///` XML doc comments:

> "Use single-line comments (`//`) for brief explanations... For describing
> methods, classes, fields, and all public members use XML comments."
https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions#comment-style

XML doc comments differ structurally from ordinary comments: the compiler
validates them against the signature (`<param>` names must match), can emit a
warning (`CS1591`) when missing from a public member, and downstream tools
(DocFX, Sandcastle, Doxygen) turn them into the interface contract users read
instead of the implementation:
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/xmldoc/
This makes `///` on a public API structurally an Ousterhout-style interface
comment, not a Martin-style inline one — the two authors' disagreement mostly
evaporates here, since both would keep it.

The Framework Design Guidelines book (Cwalina & Abrams, 2nd ed., 2008) is the
print source behind Microsoft's API guidance; its web presence
(https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/) is
naming-focused and carries no dedicated comments chapter online — flagged
**[unverified]** for the book's exact wording beyond what the XML-doc pages
above establish.

### Jeff Atwood, "Coding Without Comments," Coding Horror (2008)
Position: comments are a last resort after refactoring is exhausted, closest
in spirit to Fowler's deodorant framing but stated more absolutely.

> "You should always write your code as if comments didn't exist... when you
> can't possibly imagine any conceivable way your code could be changed to
> become more straightforward and obvious — then, and only then, should you
> feel compelled to add a comment." And: "if you feel your code is too complex
> to understand without comments, your code is probably just bad."
https://blog.codinghorror.com/coding-without-comments/

### "Comments as claims" / comments as falsifiable statements
No essay by Hillel Wayne under this exact title was found — **[unverified]**
that he wrote one; his public writing (https://buttondown.com/hillelwayne/)
concentrates on formal methods and testing, not this specific framing. The
closest documented version of the "a comment is a claim that can go stale or be
wrong" argument is John Sonmez-adjacent/independent blogger John Y's "Comments
Are Lies!" (2012), which frames every comment as an implicit, unchecked
assertion about the code:
> An interface comment claiming a parameter is `double value` when the
> signature actually takes `const string&` is the failure mode: "Unit-tests are
> of course the best documentation for any code. They are living documents
> that you can execute at any time." — https://www.johnsy.com/blog/2012/10/31/comments-are-lies/
This is the practical argument for the taxonomy's replacement column: prefer
an assertion, test, or type over a comment wherever the claim is checkable,
because only checkable forms get invalidated automatically when they go false.

**A published pushback for balance:** Tom Moertel, "Beyond Clean Code: Why Your
Comments Matter" (2026), directly challenges Martin's "comments are always
failures" line: some information (design rationale, "why this and not the
obvious alternative") is genuinely easier to state in English than to encode
in ever-more-contorted code structure.
https://blog.moertel.com/posts/2026-07-27-beyond-clean-code-why-your-comments-matter.html
His two-sentence case: forcing every "why" into names and structure produces
code *more* convoluted than a short comment would have, because naming and
control flow are the wrong medium for arguing against alternatives the reader
can't see. The near-zero-comment counter is that this information usually
survives better in a commit message or an ADR than inline, since it needn't be
re-read every time the function is.

**Net position for this policy:** every authority above, including the ones
most hostile to comments (Martin, Fowler, Atwood), reserves an exception for
information the code structurally cannot carry — the interface contract and
the non-obvious "why." Ousterhout is the only one who treats that exception as
the *normal* case rather than a rare escape hatch; the near-zero-comment policy
sides with Martin/Fowler/Atwood on defaults and with Ousterhout only for the
specific classes in §6.

---

## 2. Taxonomy of comment classes, with verdicts and replacements

| Class | Verdict | Why | Replacement when forbidden |
|---|---|---|---|
| Restating the code ("increment i") | Forbidden | Fails Ousterhout's "someone who never saw the code could write this from the code" test (ch. 13.2); Google C++ "Do not state the obvious" | Better name; delete |
| Section headers (`// ==== Setup ====`) | Forbidden | Signals the function/file is too long to see its own structure; Fowler: extract instead of label | Extract method/class; split file |
| Commented-out code | Forbidden | Dead code masquerading as documentation; source control already has history | Delete; rely on git history/branch |
| `TODO` / `FIXME` / `HACK` | Forbidden as free text; allowed only as a ticket pointer | Untracked TODOs rot silently (Sonar S1135/S1134 exist because of this) | Link to an issue tracker ticket (`// see: PROJ-123`), or fix now |
| Author / date / change history | Forbidden | `git blame`/`git log` already answer this, more reliably | `git blame`, commit message |
| License headers | Allowed (exempt, not evaluated against the policy) | Legal requirement, not documentation of behavior; Google C++ requires it | n/a — required boilerplate |
| XML doc comments on public API (`///`) | Allowed | Compiler-checked interface contract (`CS1591`); Ousterhout's "interface comment," not an inline comment; consumed by tooling, not just readers | n/a |
| The "why" comment (non-obvious reason) | Allowed, with prefix | Exactly the class every authority (including Martin/Atwood) carves out | `// why: ...` |
| Workaround for an external bug, with a link | Allowed, with prefix, link mandatory | The reason is unknowable from the code; the link makes it checkable and lets someone remove it once fixed upstream | `// workaround: <link>` |
| Performance measurement justifying an odd shape | Allowed, with prefix, numbers/link mandatory | An unintuitive structure otherwise reads as a bug; the measurement is the falsifiable claim | `// perf: <benchmark link or numbers>`; better: a benchmark test that fails if reverted |
| Invariants/preconditions the type system can't express | Allowed, with prefix | C#'s type system can't express "list must be sorted" or "index < length"; Ousterhout ch. 13.5 | `// invariant: ...`; better where possible: a guard clause + `Debug.Assert`/exception |
| Warning about a non-obvious consequence ("changing this order breaks X") | Allowed, with prefix | Prevents a specific, real regression that isn't visible from the code around it | `// warn: ...`; better: a test that encodes the constraint |
| References to a spec/RFC/ticket | Allowed, with prefix | Points to a checkable external source of truth instead of re-deriving it in prose | `// see: <link>` |
| Regex or magic-number explanations | Allowed only if the number/pattern can't be named | Usually a naming failure | Named constant; if genuinely unnameable, `// why:` with a worked example |
| `#pragma`/suppression justifications | Allowed, justification mandatory | A suppressed warning without a reason is an unreviewed risk | `#pragma warning disable CSxxxx // why: ...` / `[SuppressMessage(..., Justification = "...")]` |
| Shell script header comment (shebang + one-line purpose) | Allowed, minimal | Tooling convention (`shellcheck`/`man`), not prose commentary | Keep to shebang + one line; longer purpose goes in a README |
| Comments generated by tools (IDE stubs, codegen banners) | Forbidden if left unedited | Empty/boilerplate Javadoc is worse than none (Sonar S4663 exists for this) | Delete stub or fill with a real `why`/contract; regenerate rather than hand-edit codegen banners |

---

## 3. The pre-write test

Formulations found in the sources:
- Ousterhout: *"Could someone who has never seen the code write the comment
  just by looking at the code next to the comment?"* (ch. 13.2) — if yes, don't
  write it.
- Henney: *"Comment what the code cannot say, not simply what it does not
  say."* — the code's current silence isn't sufficient justification; ask
  whether it's structurally unable to say it.
- Atwood: *"Write your code as if comments didn't exist"* — first exhaust
  rename/extract, then ask if anything is left over.
- johnsy.com's "Comments Are Lies" framing: a comment is an unchecked claim —
  ask whether it can be made checkable (test, assertion, link) instead of
  staying prose.

**Three-question test for a low-effort model to apply mechanically, in order:**

1. **Derivable?** Can this fact be obtained by reading the code, its
   identifier names, its type signature, its tests, or a doc file already in
   the repo? → If yes, **do not write the comment**; fix the name/extract a
   method/add a test instead.
2. **Checkable?** Is this a claim that could be made a checkable artifact
   instead of prose — a type, a guard clause + exception, a `Debug.Assert`, a
   unit test, a benchmark, a linked ticket? → If yes, **prefer the checkable
   artifact**; only fall back to a comment if the checkable form doesn't exist
   in the language/toolchain today (write the comment *and* file the ticket to
   replace it).
3. **Anchored?** Does the comment carry an allowed-class prefix (§6) and, where
   required, a link/number that lets a future reader or a hook verify it's
   still true? → If no, **rewrite until it has one**, or delete it.

A comment that fails (1) is forbidden outright. A comment that passes (1) but
fails (3) is unanchored prose and should be tightened before it's written, not
after.

---

## 4. Evidence on comment rot and maintenance cost

- Fluri, Würsch & Gall, "Do Code and Comments Co-Evolve?," WCRE 2007, pp.
  70–79 (https://ieeexplore.ieee.org/document/4400153/): across ArgoUML,
  Azureus and JDT Core, only 23%, 52% and 43% respectively of comment changes
  were triggered by a source-code change at all — most comments are edited
  independently of the code they sit next to. Of the comment changes that
  *were* code-triggered, 97% landed in the same revision, i.e. the remainder
  of code changes left their neighboring comments untouched.
- Fluri, Würsch, Giger & Gall, "Analyzing the Co-evolution of Comments and
  Source Code," *Software Quality Journal* 17(4):367–394, 2009,
  https://doi.org/10.1007/s11219-009-9075-x — 8-system follow-up; newly added
  code is rarely commented, and comments don't catch up later either.
- Ibrahim, Bettenburg, Adams & Hassan, "On the Relationship between Comment
  Update Practices and Software Bugs," *JSS* 85(10):2293–2304, 2012,
  https://doi.org/10.1016/j.jss.2011.09.019 — files whose comment-update
  behavior is *inconsistent* (sometimes updated, sometimes not) show a
  measurably higher bug-introduction rate than files updated uniformly: the
  danger is uneven maintenance, not the presence of comments per se.
- Wen, Nagy, Bavota & Lanza, "A Large-Scale Empirical Study on Code-Comment
  Inconsistencies," ICSE 2019
  (https://csnagy.github.io/research/pdfs/2019/Wen2019-preprint.pdf) — largest
  study to date (1,500 Java projects, 3.3M commits, 1.3B AST-level changes);
  confirms the phenomenon is structurally recurring, not anecdotal.
- Huang, Chen, Chen & Zhou, "Are Your Comments Outdated?," 2024/2025,
  https://doi.org/10.1002/smr.2718 (preprint https://arxiv.org/abs/2403.00251):
  a classifier (CoCC) detects outdated comments at >90% precision, trained on
  real outdated-comment instances mined from 22 open-source Java projects.
- Radmanesh, Imani, Ahmed & Moshirpour, "Investigating the Impact of Code
  Comment Inconsistency on Bug Introducing," 2024,
  https://arxiv.org/abs/2409.10781 — commits with inconsistent code-comment
  changes are **~1.5× more likely** to be bug-introducing than consistent
  ones, strongest immediately after the inconsistency appears.
- Practitioner claims that "most comments in production code are wrong or
  stale" are **[unverified]** as a specific figure — repeated folklore, not a
  cited measurement. The *qualitative* direction (comments rot; uneven
  maintenance correlates with bugs) is evidenced above; no percentage here is
  attributed to blog commentary rather than the papers cited.

---

## 5. How lint tools enforce comment policy today

**SonarSource (sonar-dotnet / SonarQube/Cloud), C#:**
- `S125` "Sections of code should not be commented out" (message: "Remove this
  commented out code."); canonical page https://rules.sonarsource.com/csharp/RSPEC-125/
  — verified against the analyzer source itself since the rules.sonarsource.com
  host was unreachable from this environment:
  https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/src/SonarAnalyzer.CSharp/Rules/CommentedOutCode.cs
- `S1135` "Track uses of 'TODO' tags" and `S1134` "Track uses of 'FIXME' tags,"
  both code-smell severity (surfaced, not forbidden), defined together at
  https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/src/SonarAnalyzer.Core/Rules/CommentKeywordBase.cs
  (canonical pages .../RSPEC-1135/ and .../RSPEC-1134/).
- `S4663` "Comments should not be empty" —
  https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/src/SonarAnalyzer.Core/Rules/CommentsShouldNotBeEmptyBase.cs
  — relevant to the "comments generated by tools" row: an empty `///` IDE stub
  triggers this.

**StyleCop Analyzers (DotNetAnalyzers/StyleCopAnalyzers), C#:**
- `SA1600` ElementsMustBeDocumented — flags a public/protected element with no
  XML doc header at all:
  https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/SA1600.md
- `SA1005` SingleLineCommentsMustBeginWithSingleSpace and `SA1120`
  CommentsMustContainText — formatting/emptiness rules, not content rules:
  https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/SA1005.md ,
  .../SA1120.md
- Roslyn compiler warning `CS1591` "Missing XML comment for publicly visible
  type or member" fires whenever `GenerateDocumentationFile`/`DocumentationFile`
  is set and a public member lacks `///`:
  https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-messages/cs1591

All of the above are **presence/quality** rules — they punish *missing* or
*malformed* documentation, the opposite direction from a near-zero-comment
policy. Inverting them for this policy means: keep `S125`/`S4663`/`SA1005`/
`SA1120` as-is (they still catch genuine junk), but do **not** enable
`SA1600`/`CS1591` project-wide (they would mandate exactly the boilerplate the
policy wants to avoid on non-public or trivial members); instead add a custom
rule — a Roslyn analyzer or a pre-commit/CI regex/AST scan — that fails the
build on any `//` or `///` comment line that does **not** match one of the
allowed-class prefixes in §6, which is the mirror image of `SA1600`: "elements
must not be commented unless the comment is one of these kinds," rather than
"elements must be commented."

**Shell:** ShellCheck (https://www.shellcheck.net/wiki/) has **no rule about
comment presence, restatement, or content** — its comment-adjacent rules
(`SC1120`, `SC1127`) are purely about comment *syntax* interacting with
here-docs and `#`-vs-other-shell dialects, not about whether a comment should
exist or what it should say. A near-zero-comment hook for shell scripts must
be a separate custom check (grep/AST over the token stream for `#` lines not
matching the allowed prefixes) — there is no existing linter to lean on for
content policy, only for shebang/quoting/syntax correctness.

---

## 6. Recommended allowed-class list for the policy

Format: a hook recognizes the class by a mandatory lowercase prefix immediately
after the comment delimiter. Anything not matching one of these, in a `//` or
`#` comment, is rejected.

| Prefix | Class | One-line reason it's allowed |
|---|---|---|
| `// why:` / `# why:` | Non-obvious rationale for a design/implementation choice | The reason isn't derivable from the code, only from the decision process (Ousterhout ch. 13.8, Moertel) |
| `// invariant:` / `# invariant:` | A precondition/postcondition/invariant the type system can't express | C#/shell can't encode "sorted," "non-negative," "caller holds lock" in the signature |
| `// warn:` | A non-obvious consequence of changing this code | Prevents a specific regression that isn't visible from local context (Clean Code's "warning of consequences") |
| `// see:` | Link to a spec/RFC/ticket/design doc | Points to a checkable external source instead of re-deriving it in prose |
| `// workaround:` (link required) | External bug workaround | Unknowable from the code; the link is what makes it falsifiable/removable later |
| `// perf:` (numbers or benchmark link required) | Performance measurement justifying an odd code shape | Without it, an unintuitive structure looks like a bug waiting to be "fixed" back to the intuitive, slower form |
| `///` XML doc on a genuinely public, externally-consumed API | Interface contract | Compiler-checked (`CS1591`), tool-consumed, is the interface not an inline aside (Ousterhout ch. 13.5; Microsoft XML doc conventions) |
| `#pragma warning disable CSxxxx // why: ...` / `[SuppressMessage(Justification = "...")]` | Suppression justification | An unexplained suppression is an unreviewed risk; the justification is mandatory, not optional |
| `#!/usr/bin/env bash` + one line of purpose | Shell script header | Tooling/discoverability convention, capped at one line — longer purpose belongs in a README, not the header |

**Forbidden even with a prefix attempt:** restating the code, section-header
banners, commented-out code, author/date/history, free-text `TODO`/`FIXME`/
`HACK` with no ticket link, and any comment whose content is identical to (or a
synonym-substitution of) the name of the thing it decorates — Ousterhout's "Red
Flag: Comment Repeats Code" and the corresponding Google C++ "Don't state the
obvious" rule apply regardless of prefix. A `// why:` comment that just restates
the function name in prose form is not a `why`; the hook's prefix check is
necessary but not sufficient, and a model applying §3's test should still run
question 1 (Derivable?) before trusting the prefix.

---

## Sources

1. Robert C. Martin, *Clean Code*, ch. 4 — sample chapter: https://ptgmedia.pearsoncmg.com/images/9780132350884/samplepages/9780132350884.pdf
2. John Ousterhout, *A Philosophy of Software Design*, 2nd ed., ch. 12–13 — book page: https://web.stanford.edu/~ouster/cgi-bin/book.php ; text verified against https://milkov.tech/assets/psd.pdf
3. Kevlin Henney, "Comment Only What the Code Cannot Say," in *97 Things Every Programmer Should Know*: https://97-things-every-x-should-know.gitbooks.io/97-things-every-programmer-should-know/content/en/thing_17/
4. Martin Fowler, *Refactoring*, 2nd ed. — smells catalog: https://refactoring.com/catalog/ ; code smell background: https://martinfowler.com/bliki/CodeSmell.html
5. Google C++ Style Guide, "Comments": https://google.github.io/styleguide/cppguide.html#Comments
6. Google Java Style Guide, §7 "Javadoc": https://google.github.io/styleguide/javaguide.html#s7-javadoc
7. Microsoft, ".NET Coding Conventions - C#," comment style: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions#comment-style
8. Microsoft, "XML documentation comments": https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/xmldoc/
9. Microsoft, "Compiler Warning CS1591": https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-messages/cs1591
10. Krzysztof Cwalina & Brad Abrams, *Framework Design Guidelines*, 2nd ed. (2008); web hub: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/ [unverified: no online chapter specifically on comments]
11. Jeff Atwood, "Coding Without Comments," Coding Horror: https://blog.codinghorror.com/coding-without-comments/
12. John Y, "Comments Are Lies!": https://www.johnsy.com/blog/2012/10/31/comments-are-lies/
13. Tom Moertel, "Beyond Clean Code: Why Your Comments Matter": https://blog.moertel.com/posts/2026-07-27-beyond-clean-code-why-your-comments-matter.html
14. Fluri, Würsch & Gall, "Do Code and Comments Co-Evolve?," WCRE 2007: https://ieeexplore.ieee.org/document/4400153/
15. Fluri, Würsch, Giger & Gall, "Analyzing the Co-evolution of Comments and Source Code," *Software Quality Journal* 17(4), 2009: https://doi.org/10.1007/s11219-009-9075-x
16. Ibrahim, Bettenburg, Adams & Hassan, "On the Relationship between Comment Update Practices and Software Bugs," *JSS* 85(10), 2012: https://doi.org/10.1016/j.jss.2011.09.019
17. Wen, Nagy, Bavota & Lanza, "A Large-Scale Empirical Study on Code-Comment Inconsistencies," ICSE 2019: https://csnagy.github.io/research/pdfs/2019/Wen2019-preprint.pdf
18. Huang, Chen, Chen & Zhou, "Are Your Comments Outdated?," 2024/2025: https://doi.org/10.1002/smr.2718 (preprint https://arxiv.org/abs/2403.00251)
19. Radmanesh, Imani, Ahmed & Moshirpour, "Investigating the Impact of Code Comment Inconsistency on Bug Introducing," 2024: https://arxiv.org/abs/2409.10781
20. SonarSource rule S125 (Commented-out code): https://rules.sonarsource.com/csharp/RSPEC-125/ ; implementation: https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/src/SonarAnalyzer.CSharp/Rules/CommentedOutCode.cs
21. SonarSource rule S1135/S1134 (TODO/FIXME): https://rules.sonarsource.com/csharp/RSPEC-1135/ ; implementation: https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/src/SonarAnalyzer.Core/Rules/CommentKeywordBase.cs
22. SonarSource rule S4663 (empty comment): implementation https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/src/SonarAnalyzer.Core/Rules/CommentsShouldNotBeEmptyBase.cs
23. StyleCop Analyzers SA1600, SA1005, SA1120: https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/SA1600.md , .../SA1005.md , .../SA1120.md
24. ShellCheck wiki (no comment-content rules): https://www.shellcheck.net/wiki/
