[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$pluginRoot = Split-Path -Parent $PSScriptRoot
$orchestrationRoot = Join-Path $pluginRoot 'orchestration'
$hookScript = Join-Path $pluginRoot 'scripts\mandatory-agent-reminder.ps1'
$parentTranscript = Join-Path $PSScriptRoot 'fixtures\parent-transcript.jsonl'
$childTranscript = Join-Path $PSScriptRoot 'fixtures\child-transcript.jsonl'
$sameTurnTranscript = Join-Path $PSScriptRoot 'fixtures\same-turn-transcript.jsonl'
$newTurnTranscript = Join-Path $PSScriptRoot 'fixtures\new-turn-transcript.jsonl'
$script:results = New-Object 'System.Collections.Generic.List[object]'

function Add-Result {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Pass,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $script:results.Add([pscustomobject]@{
        Check  = $Name
        Pass   = $Pass
        Detail = $Detail
    }) | Out-Null
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
}

function Invoke-HookRaw {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RawInput,

        [Parameter(Mandatory = $false)]
        [string]$ScriptPath = $hookScript
    )

    $outputLines = @(
        $RawInput |
            & powershell.exe `
                -NoProfile `
                -NonInteractive `
                -ExecutionPolicy Bypass `
                -File $ScriptPath 2>&1
    )
    $processExitCode = $LASTEXITCODE
    $rawOutput = ($outputLines | ForEach-Object { [string]$_ }) -join "`n"

    if ($processExitCode -ne 0) {
        throw "Hook process exited with code ${processExitCode}: $rawOutput"
    }
    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        throw 'Hook process returned empty output.'
    }

    return $rawOutput | ConvertFrom-Json -ErrorAction Stop
}

function Invoke-PluginHook {
    param(
        [Parameter(Mandatory = $true)]
        [int]$InvocationNumber,

        [Parameter(Mandatory = $true)]
        [string]$TranscriptPath,

        [Parameter(Mandatory = $false)]
        [string]$Root = $pluginRoot,

        [Parameter(Mandatory = $false)]
        [string]$ScriptPath = $hookScript
    )

    $payload = [ordered]@{
        invocationNum         = $InvocationNumber
        workspacePaths        = @($Root)
        transcriptPath        = $TranscriptPath
        artifactDirectoryPath = ''
    }
    return Invoke-HookRaw `
        -RawInput ($payload | ConvertTo-Json -Depth 8 -Compress) `
        -ScriptPath $ScriptPath
}

function Get-EmbeddedJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    $escapedTag = [regex]::Escape($Tag)
    $match = [regex]::Match(
            $Message,
            "<$escapedTag>\s*(.*?)\s*</$escapedTag>",
            [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) {
        throw "Embedded JSON tag was not found: $Tag"
    }
    $parsed = $match.Groups[1].Value |
            ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [System.Array]) {
        foreach ($item in $parsed) {
            Write-Output $item
        }
        return
    }
    return $parsed
}

function Test-TemporaryAutoDiscovery {
    $tempBase = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()
    )
    $tempRoot = Join-Path `
        $tempBase `
        ('antigravity-adaptive-test-' + [guid]::NewGuid().ToString('N'))
    $tempPluginRoot = Join-Path $tempRoot 'plugin'

    try {
        [void](New-Item -ItemType Directory -Path $tempPluginRoot -Force)
        Get-ChildItem -LiteralPath $pluginRoot -Force |
            Copy-Item -Destination $tempPluginRoot -Recurse -Force

        $fixtureDirectory = Join-Path `
            $tempPluginRoot `
            'orchestration\agents\temporary-design-specialist'
        [void](New-Item -ItemType Directory -Path $fixtureDirectory -Force)

        $fixtureProfile = [ordered]@{
            '$schema'      = '../../schemas/agent.schema.json'
            schemaVersion = 2
            id            = 'temporary-design-specialist'
            displayName   = 'Temporary Design Specialist'
            description   = 'Validates automatic discovery of a future conditional design profile.'
            systemPrompt  = 'SYSTEM.md'
            skills        = @('senior-expert-mode')
            routing       = [ordered]@{
                stage        = 'wave-1'
                activation   = 'conditional'
                priority     = 60
                cost         = 'medium'
                capabilities = @('interface-design')
                taskTypes    = @('design-review')
                triggers     = @('design')
                exclusions   = @('greeting')
            }
            runtime       = [ordered]@{
                kind                = 'custom'
                enableMcpTools      = $false
                enableWriteTools    = $false
                enableSubagentTools = $false
            }
            outputContract = [ordered]@{
                format           = 'markdown'
                requiredSections = @(
                    'Status',
                    'Findings',
                    'Evidence',
                    'Uncertainty',
                    'Recommendation'
                )
                evidenceRequired = $true
            }
        }

        [System.IO.File]::WriteAllText(
                (Join-Path $fixtureDirectory 'agent.json'),
                ($fixtureProfile | ConvertTo-Json -Depth 16),
                $utf8NoBom
        )
        [System.IO.File]::WriteAllText(
                (Join-Path $fixtureDirectory 'SYSTEM.md'),
                "# Temporary Design Specialist`n`nReturn the configured sections.",
                $utf8NoBom
        )

        $tempHook = Join-Path `
            $tempPluginRoot `
            'scripts\mandatory-agent-reminder.ps1'
        $tempTranscript = Join-Path `
            $tempPluginRoot `
            'tests\fixtures\parent-transcript.jsonl'
        $result = Invoke-PluginHook `
            -InvocationNumber 0 `
            -TranscriptPath $tempTranscript `
            -Root $tempPluginRoot `
            -ScriptPath $tempHook
        $message = [string]@($result.injectSteps)[0].ephemeralMessage
        $catalog = @(
            Get-EmbeddedJson `
                -Message $message `
                -Tag 'discovered_agent_catalog_json'
        )
        $fixtureMatches = @(
            $catalog |
                Where-Object {
                    [string]$_.id -eq 'temporary-design-specialist'
                }
        )

        return $catalog.Count -eq 7 -and $fixtureMatches.Count -eq 1
    } finally {
        $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
        $safePrefix = $tempBase.TrimEnd(
                [char[]]@(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar
                )
        ) + [System.IO.Path]::DirectorySeparatorChar

        if ($resolvedTempRoot.StartsWith(
                $safePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
        ) -and
                (Split-Path -Leaf $resolvedTempRoot).StartsWith(
                        'antigravity-adaptive-test-'
                ) -and
                (Test-Path -LiteralPath $resolvedTempRoot)) {
            Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
        }
    }
}

try {
    $requiredFiles = @(
        (Join-Path $pluginRoot 'README.md'),
        (Join-Path $pluginRoot 'CONTRIBUTING.md'),
        (Join-Path $pluginRoot 'plugin.json'),
        (Join-Path $pluginRoot 'hooks.json'),
        (Join-Path $orchestrationRoot 'team.json'),
        (Join-Path $orchestrationRoot 'schemas\team.schema.json'),
        (Join-Path $orchestrationRoot 'schemas\agent.schema.json'),
        $hookScript,
        $parentTranscript,
        $childTranscript,
        $sameTurnTranscript,
        $newTurnTranscript
    )
    $missingFiles = @(
        $requiredFiles |
            Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
    )
    Add-Result `
        -Name 'Required files exist' `
        -Pass ($missingFiles.Count -eq 0) `
        -Detail $(if ($missingFiles.Count -eq 0) {
            'All required files are present.'
        } else { $missingFiles -join ', ' })

    if ($missingFiles.Count -gt 0) {
        throw 'Cannot continue because required files are missing.'
    }

    $readmeText = Get-Content `
        -LiteralPath (Join-Path $pluginRoot 'README.md') `
        -Raw `
        -Encoding UTF8
    $contributingText = Get-Content `
        -LiteralPath (Join-Path $pluginRoot 'CONTRIBUTING.md') `
        -Raw `
        -Encoding UTF8
    Add-Result `
        -Name 'Distribution documentation' `
        -Pass (
            $readmeText.Contains('# Antigravity Adaptive Two-Wave Team') -and
            $readmeText.Contains('independent community project') -and
            $readmeText.Contains('## Install in Antigravity Desktop') -and
            $readmeText.Contains('## Test in Antigravity IDE') -and
            $readmeText.Contains('## Install and test with Antigravity CLI') -and
            $readmeText.Contains('agy plugin install') -and
            $readmeText.Contains('CONTRIBUTING.md') -and
            $contributingText.Contains('## Add a new agent') -and
            $contributingText.Contains('tests\run-tests.ps1') -and
            $contributingText.Contains('## Pull request checklist')
        ) `
        -Detail 'README and contributor guide cover identity, experimental status, installation surfaces, extension, and validation.'

    $jsonFiles = @(
        Get-ChildItem -LiteralPath $pluginRoot -Filter '*.json' -File
        Get-ChildItem -LiteralPath $orchestrationRoot `
            -Filter '*.json' `
            -File `
            -Recurse
    )
    $jsonErrors = @()
    foreach ($jsonFile in $jsonFiles) {
        try {
            [void](Read-JsonFile -Path $jsonFile.FullName)
        } catch {
            $jsonErrors += "$($jsonFile.FullName): $($_.Exception.Message)"
        }
    }
    Add-Result `
        -Name 'All project JSON parses' `
        -Pass ($jsonErrors.Count -eq 0) `
        -Detail $(if ($jsonErrors.Count -eq 0) {
            "$($jsonFiles.Count) JSON files are valid."
        } else { $jsonErrors -join ' | ' })

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
            $hookScript,
            [ref]$tokens,
            [ref]$parseErrors
    )
    Add-Result `
        -Name 'Hook PowerShell syntax' `
        -Pass (@($parseErrors).Count -eq 0) `
        -Detail $(if (@($parseErrors).Count -eq 0) {
            'No parser errors.'
        } else {
            (@($parseErrors) | ForEach-Object {
                "Line $($_.Extent.StartLineNumber): $($_.Message)"
            }) -join ' | '
        })

    $hooks = Read-JsonFile -Path (Join-Path $pluginRoot 'hooks.json')
    $hookEntry = $hooks.'mandatory-agent-team-reminder'
    $preInvocation = @($hookEntry.PreInvocation)
    Add-Result `
        -Name 'Hook registration' `
        -Pass (
            $hookEntry.enabled -eq $true -and
            $preInvocation.Count -eq 1 -and
            [string]$preInvocation[0].type -eq 'command' -and
            [string]$preInvocation[0].command -match
                'scripts\\mandatory-agent-reminder\.ps1'
        ) `
        -Detail 'Enabled PreInvocation command hook.'

    $team = Read-JsonFile -Path (Join-Path $orchestrationRoot 'team.json')
    $teamPropertyNames = @($team.PSObject.Properties.Name)
    Add-Result `
        -Name 'Adaptive team configuration' `
        -Pass (
            [int]$team.schemaVersion -eq 2 -and
            [string]$team.discovery.selectionMode -eq 'adaptive' -and
            [bool]$team.discovery.lazyDefinitionLoading -and
            [string]$team.routing.manager -eq 'root-coordinator' -and
            $teamPropertyNames -notcontains 'profiles'
        ) `
        -Detail 'Schema v2 uses adaptive discovery without a hardcoded profile map.'

    Add-Result `
        -Name 'Per-user-turn activation policy' `
        -Pass (
            [string]$team.activation.mode -eq 'every-root-user-turn' -and
            [string]$team.activation.turnDeduplication -eq
                'latest-user-marker' -and
            [int]$team.activation.transcriptTailLines -ge 300
        ) `
        -Detail 'Activation is tied to the latest explicit user turn instead of invocation zero.'

    $allowedReportStatuses = @($team.publicationPolicy.allowedReportStatuses)
    Add-Result `
        -Name 'Selected report integrity retained' `
        -Pass (
            [bool]$team.finalGate.requireAllSelectedReports -and
            $allowedReportStatuses.Count -eq 4 -and
            'complete' -in $allowedReportStatuses -and
            'partial' -in $allowedReportStatuses -and
            'not-applicable' -in $allowedReportStatuses -and
            'blocked' -in $allowedReportStatuses
        ) `
        -Detail 'Every selected agent must return a real structured report; honest non-complete statuses remain valid reports.'

    Add-Result `
        -Name 'Citation recovery and removal policy' `
        -Pass (
            [string]$team.publicationPolicy.missingDirectUrlAction -eq
                'recover-once-then-remove' -and
            [int]$team.publicationPolicy.maximumFocusedRecoveryAttempts -eq 1 -and
            [string]$team.publicationPolicy.domainOnlyCitationStatus -eq
                'not-supported' -and
            [string]$team.publicationPolicy.unsupportedClaimAction -eq
                'remove-claim-and-dependent-content' -and
            [string]$team.publicationPolicy.identicalDefectAction -eq
                'do-not-reverify-unchanged'
        ) `
        -Detail 'A missing direct URL gets one focused recovery attempt, then the unsupported claim and its dependants are removed.'

    Add-Result `
        -Name 'Failure marker separation' `
        -Pass (
            [string]$team.failurePolicy.executionFailureMarker -eq
                'MANDATORY_TEAM_NOT_EXECUTED' -and
            [string]$team.failurePolicy.verificationFailureMarker -eq
                'FINAL_VERIFICATION_FAILED' -and
            [string]$team.failurePolicy.executionFailureMarker -ne
                [string]$team.failurePolicy.verificationFailureMarker -and
            [string]$team.failurePolicy.afterMaxVerificationPasses -eq
                'report-verification-failure'
        ) `
        -Detail 'Execution failure and final verification failure have distinct meanings and markers.'

    $defaultProfiles = @($team.routing.defaultEvidenceProfiles)
    Add-Result `
        -Name 'Default evidence routing' `
        -Pass (
            $defaultProfiles.Count -eq 2 -and
            'official-documentation-analyst' -in $defaultProfiles -and
            'rsh-current-research' -in $defaultProfiles
        ) `
        -Detail ($defaultProfiles -join ', ')

    $requiredVerificationCases = @($team.routing.verification.requiredFor)
    Add-Result `
        -Name 'Risk-adaptive verification policy' `
        -Pass (
            [string]$team.routing.verification.mode -eq 'risk-adaptive' -and
            [string]$team.routing.verification.profile -eq
                'rigorous-verifier' -and
            [string]$team.routing.verification.controller -eq
                'root-coordinator' -and
            [string]$team.routing.verification.execution -eq
                'independent-wave-2-agent' -and
            [string]$team.routing.verification.preAudit -eq
                'manager-claim-evidence-audit' -and
            [string]$team.routing.verification.reverifyOnlyAfter -eq
                'material-draft-change' -and
            [int]$team.failurePolicy.maxVerificationPasses -eq 2 -and
            'explicit-verification' -in $requiredVerificationCases -and
            'substantive-information-or-action' -in
                $requiredVerificationCases -and
            'latest-version-or-release' -in $requiredVerificationCases -and
            'code-or-configuration-change' -in $requiredVerificationCases
        ) `
        -Detail 'The manager controls policy while an independent Wave 2 verifier performs at most two material passes.'

    Add-Result `
        -Name 'Parallel sufficiency execution policy' `
        -Pass (
            [string]$team.executionPolicy.strategy -eq
                'parallel-batched-sufficiency' -and
            [bool]$team.executionPolicy.directSourceFirst -and
            [bool]$team.executionPolicy.batchSearchQueries -and
            [bool]$team.executionPolicy.batchPageInspection -and
            [bool]$team.executionPolicy.avoidCrossLaneDuplication -and
            [bool]$team.executionPolicy.volatileClaimsRequireLiveRevalidation -and
            [bool]$team.executionPolicy.stopWhenAcceptanceCriteriaSatisfied -and
            [int]$team.executionPolicy.maximumDiscoveryRounds.light -eq 1 -and
            [int]$team.executionPolicy.maximumParallelQueries.standard -eq 5
        ) `
        -Detail 'Research keeps evidence quality while batching independent work and stopping on sufficiency.'

    $standardBudget = $team.budgets.tiers.standard
    $deepBudget = $team.budgets.tiers.deep
    Add-Result `
        -Name 'Proportional evidence budgets' `
        -Pass (
            [int]$standardBudget.officialMinimumSources -ge 2 -and
            [int]$standardBudget.independentMinimumSources -ge 3 -and
            [int]$standardBudget.independentMinimumDomains -ge 2 -and
            [int]$standardBudget.communityMinimumReports -ge 3 -and
            [int]$deepBudget.independentMinimumSources -gt
                [int]$standardBudget.independentMinimumSources -and
            [int]$deepBudget.communityMinimumPlatforms -ge 3
        ) `
        -Detail 'Standard and deep tiers require broader, independent coverage.'

    Add-Result `
        -Name 'Payload budgets' `
        -Pass (
            [int]$team.budgets.maximumHookPayloadCharacters -le 60000 -and
            [int]$team.budgets.maximumVerifierPacketCharacters -le 45000 -and
            [int]$team.budgets.maximumVerificationDigestCharactersPerAgent -le
                2500
        ) `
        -Detail 'Hook and verification capsule have explicit bounded sizes.'

    $profileFiles = @(
        Get-ChildItem `
            -LiteralPath (Join-Path $orchestrationRoot 'agents') `
            -Filter 'agent.json' `
            -File `
            -Recurse
    )
    $profileErrors = @()
    $profileIds = @()
    foreach ($profileFile in $profileFiles) {
        try {
            $profile = Read-JsonFile -Path $profileFile.FullName
            $profileIds += [string]$profile.id
            $systemPromptPath = Join-Path `
                (Split-Path -Parent $profileFile.FullName) `
                ([string]$profile.systemPrompt)

            if ([int]$profile.schemaVersion -ne 2) {
                $profileErrors += "$($profile.id) is not schema version 2."
            }
            if ([string]$profile.runtime.kind -ne 'custom' -or
                    [bool]$profile.runtime.enableWriteTools -or
                    [bool]$profile.runtime.enableSubagentTools) {
                $profileErrors += "$($profile.id) has unsafe runtime flags."
            }
            if (-not (Test-Path -LiteralPath $systemPromptPath -PathType Leaf)) {
                $profileErrors += "$($profile.id) is missing SYSTEM.md."
            }
            if ([string]$profile.routing.stage -eq 'wave-2' -and
                    [string]$profile.routing.activation -ne 'verifier') {
                $profileErrors += "$($profile.id) has invalid Wave 2 routing."
            }
            if ([string]$profile.routing.stage -eq 'wave-1' -and
                    [string]$profile.routing.activation -eq 'verifier') {
                $profileErrors += "$($profile.id) has invalid Wave 1 routing."
            }
            if (@($profile.routing.capabilities).Count -lt 1 -or
                    @($profile.routing.taskTypes).Count -lt 1 -or
                    @($profile.routing.triggers).Count -lt 1) {
                $profileErrors += "$($profile.id) has incomplete routing metadata."
            }
            foreach ($skill in @($profile.skills)) {
                $skillPath = Join-Path $pluginRoot "skills\$skill\SKILL.md"
                if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
                    $profileErrors += "$($profile.id) references missing skill: $skill"
                }
            }
        } catch {
            $profileErrors += "$($profileFile.FullName): $($_.Exception.Message)"
        }
    }
    $uniqueProfileIds = @($profileIds | Select-Object -Unique)
    Add-Result `
        -Name 'Discovered profile metadata' `
        -Pass (
            $profileFiles.Count -eq 6 -and
            $uniqueProfileIds.Count -eq 6 -and
            $profileErrors.Count -eq 0
        ) `
        -Detail $(if ($profileErrors.Count -eq 0) {
            'Six current profiles are unique, routable, read-only, and valid.'
        } else { $profileErrors -join ' | ' })

    $expectedSkills = @(
        'agent-factory',
        'agent-team-orchestrator',
        'codebase-analysis-agent',
        'community-intelligence-research',
        'evidence-reasoning-core',
        'official-documentation-research',
        'research-source-hunter',
        'rigorous-verifier-agent',
        'senior-expert-mode'
    )
    $missingSkills = @(
        $expectedSkills |
            Where-Object {
                -not (Test-Path `
                    -LiteralPath (Join-Path $pluginRoot "skills\$_\SKILL.md") `
                    -PathType Leaf)
            }
    )
    Add-Result `
        -Name 'Required skills' `
        -Pass ($missingSkills.Count -eq 0) `
        -Detail $(if ($missingSkills.Count -eq 0) {
            'All nine skills are present.'
        } else { 'Missing: ' + ($missingSkills -join ', ') })

    $skillMetadataErrors = @()
    foreach ($skillName in $expectedSkills) {
        $skillFile = Join-Path $pluginRoot "skills\$skillName\SKILL.md"
        $skillText = Get-Content -LiteralPath $skillFile -Raw -Encoding UTF8
        $frontmatter = [regex]::Match(
                $skillText,
                '\A---\r?\n(.*?)\r?\n---\r?\n',
                [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $frontmatter.Success) {
            $skillMetadataErrors += "$skillName has no valid frontmatter."
            continue
        }
        $nameMatch = [regex]::Match(
                $frontmatter.Groups[1].Value,
                '(?m)^name:\s*([^\r\n]+)\s*$'
        )
        $descriptionMatch = [regex]::Match(
                $frontmatter.Groups[1].Value,
                '(?m)^description:\s*([^\r\n]+)\s*$'
        )
        if (-not $nameMatch.Success -or
                $nameMatch.Groups[1].Value.Trim() -ne $skillName) {
            $skillMetadataErrors += "$skillName has mismatched name metadata."
        }
        if (-not $descriptionMatch.Success -or
                [string]::IsNullOrWhiteSpace(
                        $descriptionMatch.Groups[1].Value
                )) {
            $skillMetadataErrors += "$skillName has no description metadata."
        }
    }
    Add-Result `
        -Name 'Skill frontmatter metadata' `
        -Pass ($skillMetadataErrors.Count -eq 0) `
        -Detail $(if ($skillMetadataErrors.Count -eq 0) {
            'All skill names and descriptions match their folders.'
        } else { $skillMetadataErrors -join ' | ' })

    $ruleFiles = @(
        Get-ChildItem `
            -LiteralPath (Join-Path $pluginRoot 'rules') `
            -Filter '*.md' `
            -File
    )
    $ruleErrors = @()
    foreach ($ruleFile in $ruleFiles) {
        $ruleText = Get-Content -LiteralPath $ruleFile.FullName -Raw -Encoding UTF8
        if ($ruleText.Length -gt 12000) {
            $ruleErrors += "$($ruleFile.Name) exceeds 12000 characters."
        }
        if ($ruleText -match '^\s*---\s*\r?\n') {
            $ruleErrors += "$($ruleFile.Name) contains forbidden frontmatter."
        }
    }
    Add-Result `
        -Name 'Desktop rules' `
        -Pass ($ruleFiles.Count -eq 3 -and $ruleErrors.Count -eq 0) `
        -Detail $(if ($ruleErrors.Count -eq 0) {
            'Three rules exist and remain below the size limit.'
        } else { $ruleErrors -join ' | ' })

    $normalResult = Invoke-PluginHook `
        -InvocationNumber 0 `
        -TranscriptPath $parentTranscript
    $normalSteps = @($normalResult.injectSteps)
    Add-Result `
        -Name 'Root turn injection' `
        -Pass ($normalSteps.Count -eq 1) `
        -Detail "injectSteps count: $($normalSteps.Count)"
    if ($normalSteps.Count -ne 1) {
        throw 'Root hook did not produce exactly one injected instruction.'
    }

    $message = [string]$normalSteps[0].ephemeralMessage
    Add-Result `
        -Name 'Activation markers' `
        -Pass (
            $message.Contains('[MANDATORY-TEAM-HOOK:LOADED]') -and
            -not $message.Contains('[MANDATORY-TEAM-HOOK:ERROR]')
        ) `
        -Detail 'Loaded marker present without error marker.'

    Add-Result `
        -Name 'Parent request recovery' `
        -Pass (
            $message.Contains('Parent-request status: recovered-from-transcript') -and
            $message.Contains('TEST_PARENT_REQUEST_2026')
        ) `
        -Detail 'Current parent request recovered from transcript.'

    Add-Result `
        -Name 'Compact hook payload' `
        -Pass (
            $message.Length -le
                [int]$team.budgets.maximumHookPayloadCharacters -and
            $message.Length -lt 25000
        ) `
        -Detail "Payload characters: $($message.Length)"

    $catalog = @(
        Get-EmbeddedJson `
            -Message $message `
            -Tag 'discovered_agent_catalog_json'
    )
    $routingConfig = Get-EmbeddedJson `
        -Message $message `
        -Tag 'routing_config_json'
    $evidenceBudgets = Get-EmbeddedJson `
        -Message $message `
        -Tag 'evidence_budgets_json'
    $publicationPolicy = Get-EmbeddedJson `
        -Message $message `
        -Tag 'publication_policy_json'
    $executionPolicy = Get-EmbeddedJson `
        -Message $message `
        -Tag 'execution_policy_json'

    $catalogIds = @($catalog | ForEach-Object { [string]$_.id })
    $catalogDifference = @(
        Compare-Object `
            -ReferenceObject $profileIds `
            -DifferenceObject $catalogIds
    )
    Add-Result `
        -Name 'Runtime auto-discovered catalog' `
        -Pass ($catalog.Count -eq 6 -and $catalogDifference.Count -eq 0) `
        -Detail ($catalogIds -join ', ')

    $unsafeCatalogProfiles = @(
        $catalog |
            Where-Object {
                [bool]$_.enableWriteTools -or
                [bool]$_.enableSubagentTools -or
                [string]::IsNullOrWhiteSpace([string]$_.systemPromptPath)
            }
    )
    Add-Result `
        -Name 'Catalog safety and lazy paths' `
        -Pass (
            $unsafeCatalogProfiles.Count -eq 0 -and
            -not $message.Contains('<define_subagent_bundle_json>') -and
            $message.Contains('LAZY PROFILE REGISTRATION')
        ) `
        -Detail 'Catalog exposes safe paths and does not embed full definition prompts.'

    $catalogDefault = @(
        $catalog |
            Where-Object { [string]$_.activation -eq 'default-evidence' }
    )
    $catalogConditional = @(
        $catalog |
            Where-Object { [string]$_.activation -eq 'conditional' }
    )
    $catalogVerifier = @(
        $catalog |
            Where-Object { [string]$_.activation -eq 'verifier' }
    )
    Add-Result `
        -Name 'Catalog routing composition' `
        -Pass (
            $catalogDefault.Count -eq 2 -and
            $catalogConditional.Count -eq 3 -and
            $catalogVerifier.Count -eq 1
        ) `
        -Detail 'Two defaults, three conditional specialists, and one verifier.'

    Add-Result `
        -Name 'Injected routing and budget fidelity' `
        -Pass (
            [string]$routingConfig.manager -eq 'root-coordinator' -and
            [int]$evidenceBudgets.maximumVerifierPacketCharacters -eq 45000 -and
            $message.Contains('coverage audit') -and
            $message -match 'Do not invoke an\s+irrelevant profile'
        ) `
        -Detail 'Injected policy matches adaptive routing and bounded evidence configuration.'

    Add-Result `
        -Name 'Injected publication policy fidelity' `
        -Pass (
            [string]$publicationPolicy.missingDirectUrlAction -eq
                'recover-once-then-remove' -and
            [int]$publicationPolicy.maximumFocusedRecoveryAttempts -eq 1 -and
            [string]$publicationPolicy.unsupportedClaimAction -eq
                'remove-claim-and-dependent-content' -and
            $message -match 'perform at most 1\s+focused recovery attempt' -and
            $message -match 'remove the claim and every\s+recommendation'
        ) `
        -Detail 'The hook injects the configured recover-once-then-remove contract.'

    Add-Result `
        -Name 'Injected performance policy fidelity' `
        -Pass (
            [string]$executionPolicy.strategy -eq
                'parallel-batched-sufficiency' -and
            [int]$executionPolicy.maximumDiscoveryRounds.light -eq 1 -and
            [int]$executionPolicy.maximumParallelQueries.deep -eq 8 -and
            $message -match 'canonical\s+direct sources' -and
            $message.Contains('queries in one batch') -and
            $message.Contains('Stop immediately when')
        ) `
        -Detail 'The hook directs research toward direct, parallel, non-duplicated evidence and early sufficiency.'

    Add-Result `
        -Name 'Latest-version live research contract' `
        -Pass (
            $message.Contains('never a static product-guide lookup') -and
            $message.Contains('latest public release and component versions') -and
            $message.Contains('state the as-of date')
        ) `
        -Detail 'Current-version questions cannot be answered from a static generation guide.'

    Add-Result `
        -Name 'Compact verification contract' `
        -Pass (
            $message.Contains('compact verification capsule') -and
            $message.Contains('evidence digest of at most 2500 characters') -and
            $message.Contains('VERIFICATION_PACKET_TOO_LARGE') -and
            $message.Contains('Do not copy system prompts')
        ) `
        -Detail 'Wave 2 receives bounded digests instead of full prompt/report dumps.'

    $officialPrompt = Get-Content `
        -LiteralPath (Join-Path $orchestrationRoot 'agents\official-documentation-analyst\SYSTEM.md') `
        -Raw `
        -Encoding UTF8
    $rshPrompt = Get-Content `
        -LiteralPath (Join-Path $orchestrationRoot 'agents\research-source-hunter\SYSTEM.md') `
        -Raw `
        -Encoding UTF8
    $communityPrompt = Get-Content `
        -LiteralPath (Join-Path $orchestrationRoot 'agents\community-intelligence-hunter\SYSTEM.md') `
        -Raw `
        -Encoding UTF8
    Add-Result `
        -Name 'Research breadth enforcement' `
        -Pass (
            $officialPrompt.Contains('configured number of distinct relevant first-party sources') -and
            $rshPrompt.Contains('genuinely independent sources and domains') -and
            $communityPrompt.Contains('original-report and platform targets') -and
            $communityPrompt.Contains('one page or one platform')
        ) `
        -Detail 'Research lanes cannot call a standard/deep task complete after one page.'

    Add-Result `
        -Name 'Research batching and sufficiency prompts' `
        -Pass (
            $officialPrompt.Contains('one bounded batch') -and
            $officialPrompt.Contains('instead of collecting redundant pages') -and
            $rshPrompt.Contains('one bounded batch') -and
            $rshPrompt.Contains('Stop immediately when') -and
            $communityPrompt.Contains('batch platform-specific discovery queries')
        ) `
        -Detail 'Every research lane batches independent work and stops after its evidence contract is satisfied.'

    Add-Result `
        -Name 'Community direct-link and lane contract' `
        -Pass (
            $communityPrompt.ToLowerInvariant().Contains('a bare domain') -and
            $communityPrompt.Contains('not-supported') -and
            $communityPrompt.ToLowerInvariant().Contains(
                    'independent news, security, or technical publications'
            ) -and
            $rshPrompt.ToLowerInvariant().Contains(
                    'articles from independent news, security, and technical publications'
            )
        ) `
        -Detail 'Community evidence requires exact pages while independent publication articles remain in the RSH lane.'

    $verifierPrompt = Get-Content `
        -LiteralPath (Join-Path $orchestrationRoot 'agents\rigorous-verifier\SYSTEM.md') `
        -Raw `
        -Encoding UTF8
    Add-Result `
        -Name 'Verifier routing and capsule audit' `
        -Pass (
            $verifierPrompt.ToLowerInvariant().Contains(
                    'routing coverage audit'
            ) -and
            $verifierPrompt.ToLowerInvariant().Contains(
                    'bounded evidence digest'
            ) -and
            $verifierPrompt.Contains('VERIFICATION_PACKET_TOO_LARGE')
        ) `
        -Detail 'Verifier challenges routing and compact packet integrity.'

    Add-Result `
        -Name 'Verifier report and unsupported-claim semantics' `
        -Pass (
            $verifierPrompt.Contains('`partial`, `not-applicable`, or `blocked`') -and
            $verifierPrompt.ToLowerInvariant().Contains('a bare domain') -and
            $verifierPrompt.Contains('correctly removed') -and
            $message.Contains('defect fingerprint') -and
            $message.Contains('unchanged draft and the same defect') -and
            $message.Contains('FINAL_VERIFICATION_FAILED')
        ) `
        -Detail 'Verifier accepts honest reports, rejects domain-only citations, and cannot loop on an unchanged defect.'

    Add-Result `
        -Name 'Manager-controlled independent verification' `
        -Pass (
            $message.Contains('root Coordinator is the verification controller') -and
            $message.Contains('must never verify') -and
            $message.Contains('one initial independent verifier pass') -and
            $message.Contains('second and final pass') -and
            $verifierPrompt.Contains('cannot replace your independent judgment') -and
            $verifierPrompt.Contains('Never perform a third reassurance-only pass')
        ) `
        -Detail 'Verification policy lives in the manager while verdict independence remains in a separate agent.'

    $autoDiscoveryPass = Test-TemporaryAutoDiscovery
    Add-Result `
        -Name 'Future profile auto-discovery' `
        -Pass $autoDiscoveryPass `
        -Detail 'A seventh valid conditional profile was discovered in an isolated plugin copy without editing team.json.'

    $childResult = Invoke-PluginHook `
        -InvocationNumber 0 `
        -TranscriptPath $childTranscript
    Add-Result `
        -Name 'Child recursion guard' `
        -Pass (@($childResult.injectSteps).Count -eq 0) `
        -Detail 'Wrapped child request does not start root orchestration.'

    $nonzeroRootInvocation = Invoke-PluginHook `
        -InvocationNumber 7 `
        -TranscriptPath $parentTranscript
    Add-Result `
        -Name 'Nonzero root invocation activation' `
        -Pass (
            @($nonzeroRootInvocation.injectSteps).Count -eq 1 -and
            ([string]$nonzeroRootInvocation.injectSteps[0].ephemeralMessage).Contains(
                    '[MANDATORY-TEAM-HOOK:LOADED]'
            )
        ) `
        -Detail 'A real root user turn activates even when invocationNum is nonzero.'

    $sameTurnResult = Invoke-PluginHook `
        -InvocationNumber 8 `
        -TranscriptPath $sameTurnTranscript
    Add-Result `
        -Name 'Same-turn marker deduplication' `
        -Pass (@($sameTurnResult.injectSteps).Count -eq 0) `
        -Detail 'A later model call in the same user turn does not relaunch orchestration.'

    $newTurnResult = Invoke-PluginHook `
        -InvocationNumber 19 `
        -TranscriptPath $newTurnTranscript
    $newTurnSteps = @($newTurnResult.injectSteps)
    Add-Result `
        -Name 'New user turn reactivation' `
        -Pass (
            $newTurnSteps.Count -eq 1 -and
            ([string]$newTurnSteps[0].ephemeralMessage).Contains(
                    'TEST_NEW_TURN_2026'
            )
        ) `
        -Detail 'A new explicit user message reactivates the manager after an earlier turn marker.'

    $invalidInputResult = Invoke-HookRaw -RawInput '{not-valid-json'
    $invalidInputSteps = @($invalidInputResult.injectSteps)
    $failureMessage = [string]$invalidInputSteps[0].ephemeralMessage
    Add-Result `
        -Name 'Fail-closed invalid input' `
        -Pass (
            $invalidInputSteps.Count -eq 1 -and
            $failureMessage.Contains('[MANDATORY-TEAM-HOOK:ERROR]') -and
            $failureMessage.Contains('INVALID_HOOK_INPUT') -and
            $failureMessage.Contains('MANDATORY_TEAM_NOT_EXECUTED')
        ) `
        -Detail 'Malformed input produces an explicit failure packet.'

    $hookSource = Get-Content -LiteralPath $hookScript -Raw -Encoding UTF8
    Add-Result `
        -Name 'Portable hook source' `
        -Pass (
            -not $hookSource.Contains('C:\Users\Wali') -and
            -not $hookSource.Contains('2.3.0')
        ) `
        -Detail 'No personal path or fixed product version.'
} catch {
    Add-Result `
        -Name 'Test harness execution' `
        -Pass $false `
        -Detail $_.Exception.Message
}

$failed = @($script:results | Where-Object { -not $_.Pass })
$script:results | Format-Table -Wrap -AutoSize
Write-Output ''
Write-Output (
    'TOTAL={0} PASSED={1} FAILED={2}' -f
    $script:results.Count,
    ($script:results.Count - $failed.Count),
    $failed.Count
)

if ($failed.Count -gt 0) {
    exit 1
}
exit 0
