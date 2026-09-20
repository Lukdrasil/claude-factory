# SARIF as input for an agent

The text output of `dotnet build` is a bad input for an agent; it has
to parse it with regex and can easily lose context. SARIF is structured
JSON with rule ID, exact position, severity, and message.

## Enabling it

```xml
<PropertyGroup Condition="'$(ContinuousIntegrationBuild)' == 'true'">
  <ErrorLog>$(MSBuildProjectDirectory)/analysis.sarif,version=2.1</ErrorLog>
</PropertyGroup>
```

Locally:

```bash
dotnet build -p:ErrorLog=analysis.sarif,version=2.1
```

## Usage

Grouping by rule; the agent then fixes by category,
not file by file:

```bash
jq -r '.runs[].results
       | group_by(.ruleId)
       | map({rule: .[0].ruleId, count: length, message: .[0].message.text})
       | sort_by(-.count)[]' analysis.sarif
```

Errors only, with positions:

```bash
jq -r '.runs[].results[]
       | select(.level == "error")
       | "\(.locations[0].physicalLocation.artifactLocation.uri):" +
         "\(.locations[0].physicalLocation.region.startLine) " +
         "[\(.ruleId)] \(.message.text)"' analysis.sarif
```

## Why this improves agent results

1. **The message is in the data, not in the log**; the agent gets exactly
   the instruction you wrote into MessageFormat or BannedSymbols.txt.
2. **Grouping by rule**; ten occurrences of one rule get fixed with
   one understood change, not ten times from scratch.
3. **Positions are exact**; the agent doesn't edit blindly.

## GitLab integration

SARIF feeds directly into the Code Quality widget in the MR:

```yaml
artifacts:
  reports:
    codequality: analysis.sarif
```

The reviewer then sees new problems as line comments, not as a
wall of text in the job log.
