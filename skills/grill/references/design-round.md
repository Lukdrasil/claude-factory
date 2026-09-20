# Program design

The last round of the grill, over a clean ledger: the shape of the code, approved before a line of it exists.
A wrong signature costs one sentence here and a refactor after the implement phase.

Sketch the design per file: the members without bodies, and under each member at most two sentences on what
it solves. A new file by its intended path, an existing file with only the members that change. Signatures in
the stack's language, public surface only: no field, no private helper, no test. Read the code first, so an
existing type that already does the job is named, not re-declared.

The sketch must be stubbable. Block 00 of a wave declares the shape every other block builds against, so a
member it cannot stub is a merge collision. Name the constructors, the injected dependencies and every shared
abstraction or common method two blocks would both use, because they are public surface. Private members and
private helpers stay out, explicitly.

```
### `src/Export/IExporter.cs` (new)
public interface IExporter
  One export pipeline per format; the API resolves it by the request's content type.
  Task<Stream> ExportAsync(ExportRequest request, CancellationToken ct);
    Renders one request into a stream. Throws ExportFormatException for a format no pipeline handles.

### `src/Api/ExportEndpoints.cs` (existing)
  static IResult Export(ExportRequest request, IExporter exporter, CancellationToken ct)
    Replaces the inline switch; the format decision moves into the exporter.
```

Put the whole sketch to the human as one round in the interview format: a single question over the design,
your recommendation the approval, then wait. A "wrong" on any member is a `decision` row. Close it with the
human's answer, re-sketch, ask again, and repeat until the human approves as written.

The approved sketch goes verbatim into `## Program design` of plan-ready.md, and every proposal's `design:`
names the members it implements, so an implement session builds the approved shape and nothing else. Every
approved member belongs to exactly one proposal; `<plugin-root>/bin/plan-lint.sh` names a member owned by none or by two.
