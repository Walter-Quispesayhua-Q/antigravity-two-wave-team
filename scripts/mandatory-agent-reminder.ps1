Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$script:executionFailureMarker = 'MANDATORY_TEAM_NOT_EXECUTED'
$script:verificationFailureMarker = 'FINAL_VERIFICATION_FAILED'

function Write-HookResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    $json = $Result | ConvertTo-Json -Depth 32 -Compress
    [Console]::Out.Write($json)
    exit 0
}

function Write-EmptyResult {
    Write-HookResult -Result ([ordered]@{ injectSteps = @() })
}

function Write-FailureResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $safeCode = $Code -replace '[^A-Z0-9_-]', '_'
    $failureMessage = @"
[MANDATORY-TEAM-HOOK:ERROR]
The adaptive team hook executed but could not prepare a valid orchestration packet.

Error code: $safeCode
Reason: $Message

Do not simulate agents or replace executions with role headings.
Report the exact limitation and this marker:
$script:executionFailureMarker
"@

    Write-HookResult -Result ([ordered]@{
        injectSteps = @(
            [ordered]@{ ephemeralMessage = $failureMessage.Trim() }
        )
    })
}

function Read-Utf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [long]$MaximumBytes = 65536
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Required file is missing.'
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -gt $MaximumBytes) {
        throw 'Required file exceeds the permitted size.'
    }

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($Path, $strictUtf8)
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [long]$MaximumBytes = 65536
    )

    $text = Read-Utf8Text -Path $Path -MaximumBytes $MaximumBytes
    return $text | ConvertFrom-Json
}

function Resolve-SafeChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'A required relative path is empty.'
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw 'Absolute paths are not allowed in plugin configuration.'
    }

    $fullPath = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $BasePath -ChildPath $RelativePath)
    )
    $fullAllowedRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
    $trimCharacters = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $fullAllowedRoot.TrimEnd($trimCharacters) +
            [System.IO.Path]::DirectorySeparatorChar

    if (-not $fullPath.StartsWith(
            $rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'A configured path escapes the plugin root.'
    }

    return $fullPath
}

function Get-LatestUserTurnState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$HookInput,

        [Parameter(Mandatory = $true)]
        [string]$HookMarker,

        [Parameter(Mandatory = $true)]
        [int]$MaximumTailLines
    )

    $propertyNames = @($HookInput.PSObject.Properties.Name)
    if ($propertyNames -notcontains 'transcriptPath') {
        return [pscustomobject]@{
            Request                   = $null
            RequestRecovered          = $false
            MarkerSeenAfterLatestUser = $false
        }
    }

    $transcriptPath = [string]$HookInput.transcriptPath
    if ([string]::IsNullOrWhiteSpace($transcriptPath) -or
            -not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) {
        return [pscustomobject]@{
            Request                   = $null
            RequestRecovered          = $false
            MarkerSeenAfterLatestUser = $false
        }
    }

    $latestUserRequest = $null
    $markerSeenAfterLatestUser = $false

    try {
        $candidateLines = Get-Content `
            -LiteralPath $transcriptPath `
            -Tail $MaximumTailLines `
            -Encoding UTF8

        foreach ($line in $candidateLines) {
            try {
                $entry = $line | ConvertFrom-Json
                $entryProperties = @($entry.PSObject.Properties.Name)
                $isExplicitUserInput =
                    $entryProperties -contains 'source' -and
                    $entryProperties -contains 'type' -and
                    [string]$entry.source -eq 'USER_EXPLICIT' -and
                    [string]$entry.type -eq 'USER_INPUT'
                $isRoleUserInput =
                    $entryProperties -contains 'role' -and
                    [string]$entry.role -eq 'user'

                if (($isExplicitUserInput -or $isRoleUserInput) -and
                        $entryProperties -contains 'content' -and
                        $entry.content -is [string] -and
                        -not [string]::IsNullOrWhiteSpace(
                                [string]$entry.content
                        )) {
                    $latestUserRequest = [string]$entry.content
                    $markerSeenAfterLatestUser = $false
                    continue
                }

                if ($null -ne $latestUserRequest -and
                        $entryProperties -contains 'content' -and
                        $entry.content -is [string] -and
                        ([string]$entry.content).Contains($HookMarker)) {
                    $markerSeenAfterLatestUser = $true
                }
            } catch {
                # Ignore incomplete or non-JSON transcript lines.
            }
        }
    } catch {
        return [pscustomobject]@{
            Request                   = $null
            RequestRecovered          = $false
            MarkerSeenAfterLatestUser = $false
        }
    }

    return [pscustomobject]@{
        Request                   = $latestUserRequest
        RequestRecovered          = -not [string]::IsNullOrWhiteSpace(
                $latestUserRequest
        )
        MarkerSeenAfterLatestUser = $markerSeenAfterLatestUser
    }
}

function Convert-ToStringArray {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Values
    )

    return @($Values | ForEach-Object { [string]$_ })
}

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-FailureResult `
        -Code 'EMPTY_HOOK_INPUT' `
        -Message 'PreInvocation did not provide its JSON input.'
}

try {
    $hookInput = $rawInput | ConvertFrom-Json
} catch {
    Write-FailureResult `
        -Code 'INVALID_HOOK_INPUT' `
        -Message 'PreInvocation input was not valid JSON.'
}

$hookInputProperties = @($hookInput.PSObject.Properties.Name)
if ($hookInputProperties -notcontains 'invocationNum') {
    Write-FailureResult `
        -Code 'MISSING_INVOCATION_NUMBER' `
        -Message 'PreInvocation did not provide invocationNum.'
}

try {
    $invocationNumber = [int]$hookInput.invocationNum
} catch {
    Write-FailureResult `
        -Code 'INVALID_INVOCATION_NUMBER' `
        -Message 'PreInvocation invocationNum was not an integer.'
}

try {
    $scriptPath = [System.IO.Path]::GetFullPath(
            $MyInvocation.MyCommand.Path
    )
    $scriptDirectory = Split-Path -Parent $scriptPath
    $pluginRoot = Split-Path -Parent $scriptDirectory
    $orchestrationRoot = Join-Path $pluginRoot 'orchestration'
    $skillsRoot = Join-Path $pluginRoot 'skills'

    $teamPath = Join-Path $orchestrationRoot 'team.json'
    $team = Read-JsonFile -Path $teamPath -MaximumBytes 65536
    $teamProperties = @($team.PSObject.Properties.Name)
    $requiredTeamProperties = @(
        'schemaVersion',
        'id',
        'activation',
        'coordinator',
        'discovery',
        'routing',
        'waves',
        'budgets',
        'executionPolicy',
        'publicationPolicy',
        'failurePolicy',
        'finalGate'
    )

    foreach ($property in $requiredTeamProperties) {
        if ($teamProperties -notcontains $property) {
            throw 'team.json is missing a required property.'
        }
    }

    if ([int]$team.schemaVersion -ne 2) {
        throw 'team.json must use schemaVersion 2.'
    }

    $hookMarker = [string]$team.activation.hookLoadedMarker
    $childMarkerPrefix = [string]$team.activation.childTaskMarkerPrefix
    $turnDeduplication = [string]$team.activation.turnDeduplication
    $transcriptTailLines = [int]$team.activation.transcriptTailLines
    $configuredFailureMarker =
        [string]$team.failurePolicy.executionFailureMarker
    $configuredVerificationFailureMarker =
        [string]$team.failurePolicy.verificationFailureMarker

    if ([string]::IsNullOrWhiteSpace($hookMarker) -or
            [string]::IsNullOrWhiteSpace($childMarkerPrefix) -or
            [string]::IsNullOrWhiteSpace($configuredFailureMarker) -or
            [string]::IsNullOrWhiteSpace(
                    $configuredVerificationFailureMarker
            ) -or
            $turnDeduplication -ne 'latest-user-marker' -or
            $transcriptTailLines -lt 300 -or
            $transcriptTailLines -gt 5000) {
        throw 'team.json contains an empty mandatory marker.'
    }

    $script:executionFailureMarker = $configuredFailureMarker
    $script:verificationFailureMarker =
        $configuredVerificationFailureMarker

    if ([string]$team.publicationPolicy.missingDirectUrlAction -ne
                'recover-once-then-remove' -or
            [int]$team.publicationPolicy.maximumFocusedRecoveryAttempts -ne 1 -or
            [string]$team.publicationPolicy.domainOnlyCitationStatus -ne
                'not-supported' -or
            [string]$team.publicationPolicy.unsupportedClaimAction -ne
                'remove-claim-and-dependent-content' -or
            [string]$team.publicationPolicy.identicalDefectAction -ne
                'do-not-reverify-unchanged' -or
            [int]$team.publicationPolicy.maximumIdenticalDefectRepetitions -ne 1) {
        throw 'team.json publication recovery safeguards are incomplete.'
    }

    if ([string]$team.executionPolicy.strategy -ne
                'parallel-batched-sufficiency' -or
            -not [bool]$team.executionPolicy.directSourceFirst -or
            -not [bool]$team.executionPolicy.batchSearchQueries -or
            -not [bool]$team.executionPolicy.batchPageInspection -or
            -not [bool]$team.executionPolicy.avoidCrossLaneDuplication -or
            -not [bool]$team.executionPolicy.volatileClaimsRequireLiveRevalidation -or
            -not [bool]$team.executionPolicy.stopWhenAcceptanceCriteriaSatisfied) {
        throw 'team.json execution performance safeguards are incomplete.'
    }

    if ([string]$team.routing.verification.controller -ne
                'root-coordinator' -or
            [string]$team.routing.verification.execution -ne
                'independent-wave-2-agent' -or
            [string]$team.routing.verification.preAudit -ne
                'manager-claim-evidence-audit' -or
            [string]$team.routing.verification.reverifyOnlyAfter -ne
                'material-draft-change' -or
            [int]$team.failurePolicy.maxVerificationPasses -ne 2) {
        throw 'team.json verifier management safeguards are incomplete.'
    }

    if ([bool]$team.coordinator.spawnCoordinatorSubagent -or
            [string]$team.routing.manager -ne 'root-coordinator') {
        throw 'The root agent must remain the Coordinator and routing manager.'
    }

    $requiredFinalGates = @(
        'requireRoutingDecision',
        'requireCoverageAudit',
        'requireActualReports',
        'requireAllSelectedReports',
        'requireVerifierWhenRequired',
        'requirePreVerificationAudit',
        'requireDirectSourceLinks',
        'requireCommunityQualification',
        'requireUserLanguage',
        'requirePublishedVerifierVerdictWhenRun',
        'prohibitSimulatedAgents'
    )

    foreach ($gate in $requiredFinalGates) {
        if (-not [bool]$team.finalGate.$gate) {
            throw 'team.json final-gate safeguards are incomplete.'
        }
    }

    $turnState = Get-LatestUserTurnState `
        -HookInput $hookInput `
        -HookMarker $hookMarker `
        -MaximumTailLines $transcriptTailLines

    if ([bool]$turnState.MarkerSeenAfterLatestUser) {
        Write-EmptyResult
    }

    $userRequest = [string]$turnState.Request
    $requestRecoveredFromTranscript = [bool]$turnState.RequestRecovered

    if ([string]::IsNullOrWhiteSpace($userRequest)) {
        $userRequest = @'
The hook could not recover the original user request from the transcript.
The root Coordinator must replace this fallback with the actual current
parent request from its active conversation before invoking subagents.
'@
    }

    $trimmedRequest = $userRequest.TrimStart()
    $userRequestOpeningTag = '<USER_REQUEST>'
    if ($trimmedRequest.StartsWith(
            $userRequestOpeningTag,
            [System.StringComparison]::OrdinalIgnoreCase
    )) {
        $trimmedRequest = $trimmedRequest.Substring(
                $userRequestOpeningTag.Length
        ).TrimStart()
    }

    if ($trimmedRequest.StartsWith(
            $childMarkerPrefix,
            [System.StringComparison]::Ordinal
    )) {
        Write-EmptyResult
    }

    if ($userRequest.Length -gt 16000) {
        $userRequest = $userRequest.Substring(0, 16000) +
                "`n[Parent request truncated by hook at 16000 characters.]"
    }

    $workspacePaths = @()
    if ($hookInputProperties -contains 'workspacePaths' -and
            $null -ne $hookInput.workspacePaths) {
        $workspacePaths = @(
            $hookInput.workspacePaths |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    $localTime = Get-Date
    $executionTimestamp = $localTime.ToString(
            'yyyy-MM-ddTHH:mm:ssK',
            [System.Globalization.CultureInfo]::InvariantCulture
    )
    $timeZoneId = [System.TimeZoneInfo]::Local.Id

    $agentsDirectory = Resolve-SafeChildPath `
        -BasePath $orchestrationRoot `
        -RelativePath ([string]$team.discovery.agentsDirectory) `
        -AllowedRoot $pluginRoot

    if (-not (Test-Path -LiteralPath $agentsDirectory -PathType Container)) {
        throw 'The configured agent discovery directory is missing.'
    }

    $profileFileName = [string]$team.discovery.profileFileName
    if ($profileFileName -ne 'agent.json') {
        throw 'Only agent.json discovery is supported.'
    }

    $profilePaths = @(
        Get-ChildItem -LiteralPath $agentsDirectory -Directory |
            ForEach-Object {
                Join-Path -Path $_.FullName -ChildPath $profileFileName
            } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    )

    $maximumProfiles = [int]$team.discovery.maximumProfiles
    if ($profilePaths.Count -lt 1 -or
            $profilePaths.Count -gt $maximumProfiles) {
        throw 'The discovered agent count is outside the configured limit.'
    }

    $seenProfileIds = @{}
    $catalog = New-Object 'System.Collections.Generic.List[object]'

    foreach ($profilePath in $profilePaths) {
        $profile = Read-JsonFile -Path $profilePath -MaximumBytes 65536
        $profileProperties = @($profile.PSObject.Properties.Name)
        $requiredProfileProperties = @(
            'schemaVersion',
            'id',
            'displayName',
            'description',
            'systemPrompt',
            'skills',
            'routing',
            'runtime',
            'outputContract'
        )

        foreach ($property in $requiredProfileProperties) {
            if ($profileProperties -notcontains $property) {
                throw 'A discovered agent profile is missing a required property.'
            }
        }

        $profileId = [string]$profile.id
        if ([int]$profile.schemaVersion -ne 2 -or
                $profileId -notmatch '^[a-z][a-z0-9-]*$') {
            throw 'A discovered agent profile has an invalid schema version or ID.'
        }

        if ($seenProfileIds.ContainsKey($profileId)) {
            throw 'A duplicate discovered agent profile ID was found.'
        }
        $seenProfileIds[$profileId] = $true

        if ([string]$profile.runtime.kind -ne 'custom' -or
                [bool]$profile.runtime.enableWriteTools -or
                [bool]$profile.runtime.enableSubagentTools) {
            throw 'Discovered profiles must be custom, read-only, and non-delegating.'
        }

        $stage = [string]$profile.routing.stage
        $activation = [string]$profile.routing.activation
        if ($stage -notin @('wave-1', 'wave-2') -or
                $activation -notin @(
                    'default-evidence',
                    'conditional',
                    'verifier'
                )) {
            throw 'A discovered profile contains invalid routing metadata.'
        }

        if (($activation -eq 'verifier' -and $stage -ne 'wave-2') -or
                ($activation -ne 'verifier' -and $stage -ne 'wave-1')) {
            throw 'A discovered profile has an invalid stage and activation combination.'
        }

        $profileDirectory = Split-Path -Parent $profilePath
        $systemPromptPath = Resolve-SafeChildPath `
            -BasePath $profileDirectory `
            -RelativePath ([string]$profile.systemPrompt) `
            -AllowedRoot $pluginRoot

        [void](Read-Utf8Text -Path $systemPromptPath -MaximumBytes 50000)

        $profileSkills = @(
            Convert-ToStringArray -Values @($profile.skills)
        )
        if ($profileSkills.Count -lt 1) {
            throw 'A discovered profile has no declared skills.'
        }

        foreach ($skillId in $profileSkills) {
            if ($skillId -notmatch '^[a-z][a-z0-9-]*$') {
                throw 'A discovered profile contains an invalid skill ID.'
            }

            $skillPath = Resolve-SafeChildPath `
                -BasePath $skillsRoot `
                -RelativePath (Join-Path $skillId 'SKILL.md') `
                -AllowedRoot $pluginRoot

            if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
                throw 'A discovered profile references a missing skill.'
            }
        }

        $requiredSections = @(
            Convert-ToStringArray `
                -Values @($profile.outputContract.requiredSections)
        )
        if ($requiredSections.Count -lt 1) {
            throw 'A discovered profile has an empty output contract.'
        }

        $capabilities = @(
            Convert-ToStringArray -Values @($profile.routing.capabilities)
        )
        $taskTypes = @(
            Convert-ToStringArray -Values @($profile.routing.taskTypes)
        )
        $triggers = @(
            Convert-ToStringArray -Values @($profile.routing.triggers)
        )
        $exclusions = @(
            Convert-ToStringArray -Values @($profile.routing.exclusions)
        )

        if ($capabilities.Count -lt 1 -or
                $taskTypes.Count -lt 1 -or
                $triggers.Count -lt 1) {
            throw 'A discovered profile has incomplete routing metadata.'
        }

        $catalog.Add([pscustomobject][ordered]@{
            id                  = $profileId
            displayName         = [string]$profile.displayName
            description         = [string]$profile.description
            stage               = $stage
            activation          = $activation
            priority            = [int]$profile.routing.priority
            cost                = [string]$profile.routing.cost
            capabilities        = @($capabilities)
            taskTypes           = @($taskTypes)
            triggers            = @($triggers)
            exclusions          = @($exclusions)
            profilePath         = [System.IO.Path]::GetFullPath($profilePath)
            systemPromptPath    = $systemPromptPath
            skills              = @($profileSkills)
            requiredSections    = @($requiredSections)
            enableMcpTools      = [bool]$profile.runtime.enableMcpTools
            enableWriteTools    = [bool]$profile.runtime.enableWriteTools
            enableSubagentTools = [bool]$profile.runtime.enableSubagentTools
        })
    }

    $catalogById = @{}
    foreach ($record in $catalog) {
        $catalogById[[string]$record.id] = $record
    }

    $defaultEvidenceProfiles = @(
        Convert-ToStringArray `
            -Values @($team.routing.defaultEvidenceProfiles)
    )
    foreach ($profileId in $defaultEvidenceProfiles) {
        if (-not $catalogById.ContainsKey($profileId) -or
                [string]$catalogById[$profileId].activation -ne
                    'default-evidence') {
            throw 'A configured default evidence profile was not discovered.'
        }
    }

    $verifierProfileId = [string]$team.routing.verification.profile
    if (-not $catalogById.ContainsKey($verifierProfileId) -or
            [string]$catalogById[$verifierProfileId].activation -ne
                'verifier') {
        throw 'The configured verifier profile was not discovered.'
    }

    $verifierProfiles = @(
        $catalog | Where-Object { [string]$_.activation -eq 'verifier' }
    )
    if ($verifierProfiles.Count -ne 1) {
        throw 'Exactly one verifier profile must be discovered.'
    }

    $wave1Profiles = @(
        $catalog | Where-Object { [string]$_.stage -eq 'wave-1' }
    )
    if ($wave1Profiles.Count -lt $defaultEvidenceProfiles.Count -or
            $wave1Profiles.Count -gt [int]$team.routing.maximumWave1Agents) {
        throw 'The discovered Wave 1 catalog is outside the configured limit.'
    }

    $waves = @($team.waves | Sort-Object { [int]$_.order })
    if ($waves.Count -ne 2 -or
            [string]$waves[0].id -ne 'wave-1' -or
            [string]$waves[0].mode -ne 'parallel' -or
            [string]$waves[1].id -ne 'wave-2' -or
            [string]$waves[1].mode -ne 'sequential' -or
            [string]$waves[0].id -notin @($waves[1].dependsOn)) {
        throw 'The adaptive two-wave dependency graph is invalid.'
    }

    $maximumHookPayloadCharacters =
        [int]$team.budgets.maximumHookPayloadCharacters
    $maximumVerifierPacketCharacters =
        [int]$team.budgets.maximumVerifierPacketCharacters
    $maximumAgentReportCharacters =
        [int]$team.budgets.maximumAgentReportCharacters
    $maximumDigestCharacters =
        [int]$team.budgets.maximumVerificationDigestCharactersPerAgent
    $maximumVerificationPasses =
        [int]$team.failurePolicy.maxVerificationPasses
    $maximumFocusedRecoveryAttempts =
        [int]$team.publicationPolicy.maximumFocusedRecoveryAttempts
    $maximumIdenticalDefectRepetitions =
        [int]$team.publicationPolicy.maximumIdenticalDefectRepetitions

    $catalogJson = ConvertTo-Json `
        -InputObject @($catalog | Sort-Object stage, @{ Expression = 'priority'; Descending = $true }) `
        -Depth 16 `
        -Compress
    $routingJson = ConvertTo-Json `
        -InputObject $team.routing `
        -Depth 16 `
        -Compress
    $budgetsJson = ConvertTo-Json `
        -InputObject $team.budgets `
        -Depth 16 `
        -Compress
    $publicationPolicyJson = ConvertTo-Json `
        -InputObject $team.publicationPolicy `
        -Depth 16 `
        -Compress
    $executionPolicyJson = ConvertTo-Json `
        -InputObject $team.executionPolicy `
        -Depth 16 `
        -Compress
    $wave1InputsJson = ConvertTo-Json `
        -InputObject @($waves[0].requiredInputs) `
        -Compress
    $wave2InputsJson = ConvertTo-Json `
        -InputObject @($waves[1].requiredInputs) `
        -Compress
    $allowedVerdictsJson = ConvertTo-Json `
        -InputObject @($team.finalGate.allowedVerifierVerdicts) `
        -Compress
    $requestJson = ConvertTo-Json -InputObject $userRequest -Compress
    $workspaceJson = ConvertTo-Json -InputObject @($workspacePaths) -Compress
    $requestRecoveryStatus = if ($requestRecoveredFromTranscript) {
        'recovered-from-transcript'
    } else {
        'coordinator-must-replace-fallback'
    }

    $orchestrationDirective = @"
$hookMarker
The adaptive PreInvocation hook is active for this root turn.

Team ID: $([string]$team.id)
Execution timestamp: $executionTimestamp
Execution timezone: $timeZoneId
Parent-request status: $requestRecoveryStatus
Workspace paths JSON: $workspaceJson

The root agent is both Coordinator and routing manager. Never create a
Coordinator or routing-manager subagent. Do not simulate agents through
headings. Use the user's language for progress and the final answer unless the
user explicitly requests another language. Send progress only when state
materially changes.

Original user request JSON:
$requestJson

Execute this adaptive protocol:

1. ROUTING PREFLIGHT
Recover the exact objective, constraints, permissions, response language,
acceptance criteria, risk, and definition of done. Classify the request as
fast, light, standard, or deep. A fast path is allowed only when the entire
request is an exemption in routing_config_json and contains no material
current, external, local-project, verification, recommendation, or high-impact
claim.

A request for the latest, current, newest, recent, version, release, build,
update, support status, or deprecation is never a static product-guide lookup.
Classify a narrow single-fact request of this kind as at least light, select the
default evidence profiles, require live revalidation, and distinguish product
generation names from the latest public release and component versions. The
final answer must state the as-of date and cite the exact inspected release,
changelog, registry, or repository page.

For every substantive information, research, comparison, or recommendation
request, select both default-evidence profiles. Add conditional Wave 1 profiles
when their capabilities or taskTypes materially cover the request. Search words
are hints, not an exhaustive keyword gate. A future discovered specialist must
be selected when its capabilities materially own an acceptance criterion.

Perform a coverage audit before invoking: map every acceptance criterion and
material risk to the selected profile that owns it. Record one concise reason
for every selected profile and every skipped conditional profile. When routing
is genuinely uncertain, include the best-matching profile. Do not invoke an
irrelevant profile merely to reach a fixed count. Never select the verifier in
Wave 1. Respect maximumWave1Agents.

2. LAZY PROFILE REGISTRATION
The catalog was generated by scanning orchestration/agents/*/agent.json on this
turn. It is the only discovered catalog for this turn. For each selected Wave 1
profile not already registered, read exactly its systemPromptPath and make a
real define_subagent call using catalog description and runtime flags. Append
to system_prompt: activate the listed installed skills; execute only the marked
child task; do not start root orchestration. If verification is required, load
and register the configured verifier the same way. Do not load or register
unselected conditional profiles. Do not claim registration unless it succeeds.

3. WAVE 1
Build one specification for each selected Wave 1 profile. Every Prompt must
begin with the child marker plus profile ID and must include the original
request, current timestamp/timezone, workspace roots, routing decision,
evidence tier, objective, acceptance criteria, constraints, permissions, agent-
specific responsibility, work budget, stop condition, response language, and
requiredSections. Tell every agent to keep its complete report at or below
$maximumAgentReportCharacters characters and to stop at the assigned source
budget. Minimum source counts are quality targets, never permission to invent
sources; when a target cannot be met, the report must be partial and explain
why. Invoke all selected Wave 1 profiles in one real parallel invoke_subagent
call when batching is available.

Apply execution_policy_json inside every research task. Start with canonical
direct sources, issue independent lane-specific queries in one batch, inspect
independent candidate pages in parallel when tools allow it, and avoid opening
the same source in multiple lanes. Do not browse page by page when a batch can
answer the same bounded claim inventory. Use only the configured discovery
rounds and parallel-query limit for the selected tier. Stop immediately when
the acceptance criteria, applicable source targets, direct-link requirements,
and contradiction check are satisfied. Cached discovery may guide navigation,
but every volatile claim must be revalidated live.

4. WAIT AND SYNTHESIZE
Wait only for the selected profiles. Every selected execution must return a
real report and runtime identifier. A structurally complete report may have
status complete, partial, not-applicable, or blocked; status does not replace
the report. A runtime failure with no report is an execution failure. Never
wait for a skipped profile. Build the claim-level evidence ledger, reconcile
contradictions, preserve uncertainty, and produce the proposed answer. Evidence
from official, independent, community, local, professional-judgment, and future
specialist lanes must remain distinct.

5. PRE-VERIFICATION AUDIT
Map every material claim to inspected evidence. External claims require direct
human-readable links near the claim when practical. A bare domain, publisher
name, search snippet, or inaccessible result is not a direct URL and its claim
must be marked not-supported. Community material must be qualified and linked.
Local installation or runtime claims require direct local evidence.

For a missing direct URL, perform at most $maximumFocusedRecoveryAttempts
focused recovery attempt. If the exact supporting page is still not inspected,
remove the claim and every recommendation or conclusion that depends on it.
Do not send a known unsupported claim to the verifier. Keep the gap in the
internal evidence ledger only when useful. Confirm the answer uses the user's
language and correct all defects together before verification.

6. RISK-ADAPTIVE WAVE 2
The root Coordinator is the verification controller, but it must never verify
its own proposed answer. Its pre-verification claim/evidence audit is a fast
manager gate, not an independent verdict and not a verifier pass. Keep the
Rigorous Verifier as the separate Wave 2 agent so its context and judgment
remain independent.

Use routing_config_json to decide whether verification is required. It is
mandatory for every listed requiredFor condition and may be skipped only when a
listed skipFor condition fully describes the request and no required condition
applies. Record the decision and reason.

Treat every non-exempt substantive information or action request as
substantive-information-or-action, so it receives one independent verifier
pass. Greetings, acknowledgements, pure creative work, and low-risk formatting
may skip only when no material factual, external, local, recommendation,
verification, or action claim is present.

When verification is required, create a compact verification capsule containing
the original request, routing decision, selected-agent execution ledger,
evidence digest of at most $maximumDigestCharacters characters per selected
agent, evidence ledger, claim-evidence matrix, citation audit, response
language, pre-audit result, acceptance criteria, proposed answer, and relevant
source links/paths/tests. Do not copy system prompts, tool chatter, repetitive
progress, or entire raw reports. The complete capsule must be at most
$maximumVerifierPacketCharacters characters. If material evidence cannot fit,
report VERIFICATION_PACKET_TOO_LARGE instead of launching an invalid packet.
Invoke only the verifier after Wave 1 is complete.

Run exactly one initial independent verifier pass. A second and final pass is
allowed only after a material draft or evidence correction. Never perform
double or triple verification merely for reassurance.

7. CORRECTION LOOP
On verifier fail, normalize the material defect codes and affected claim IDs to
build a defect fingerprint. Group and correct all supported defects. For a
missing-link defect, use the one focused recovery attempt only if it was not
already used; otherwise remove the unsupported claim and dependent content.
Rebuild the compact capsule only after the draft materially changes.

Never invoke another verifier pass with an unchanged draft and the same defect
fingerprint. The same material fingerprint may repeat at most
$maximumIdenticalDefectRepetitions time. If the result cannot satisfy a required
acceptance criterion after truthful removal or correction, stop and report:
$script:verificationFailureMarker

Use at most $maximumVerificationPasses passes. Never hide evidence to obtain
approval.

8. FINAL GATE
Finalize only after a real routing decision and coverage audit, all selected
reports exist, and every required verification has a current allowed
verdict. If a verifier ran, disclose its verdict and pass number concisely. If
verification was correctly skipped, state that only when relevant; never invent
a verdict. If selected agents or the verifier could not execute, report the
execution limitation and:
$script:executionFailureMarker

If all required executions occurred but verification still fails after the
bounded correction process, report the unresolved verification defects and:
$script:verificationFailureMarker

Prompts beginning with the child-task marker are subagent tasks and must never
start another team.

Required Wave 1 input fields:
$wave1InputsJson

Required Wave 2 input fields:
$wave2InputsJson

Allowed verifier verdicts:
$allowedVerdictsJson

<routing_config_json>
$routingJson
</routing_config_json>

<evidence_budgets_json>
$budgetsJson
</evidence_budgets_json>

<publication_policy_json>
$publicationPolicyJson
</publication_policy_json>

<execution_policy_json>
$executionPolicyJson
</execution_policy_json>

<discovered_agent_catalog_json>
$catalogJson
</discovered_agent_catalog_json>
"@

    if ($orchestrationDirective.Length -gt $maximumHookPayloadCharacters) {
        throw 'The generated adaptive orchestration payload exceeds its configured safe size.'
    }

    Write-HookResult -Result ([ordered]@{
        injectSteps = @(
            [ordered]@{ ephemeralMessage = $orchestrationDirective.Trim() }
        )
    })
} catch {
    $diagnostic = [string]$_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($diagnostic)) {
        $diagnostic = 'No exception detail was available.'
    }

    $diagnostic = $diagnostic -replace '[\r\n]+', ' '
    if ($diagnostic.Length -gt 500) {
        $diagnostic = $diagnostic.Substring(0, 500) + '...'
    }

    Write-FailureResult `
        -Code 'PLUGIN_CONFIGURATION_INVALID' `
        -Message ("Plugin validation failed: $diagnostic")
}
