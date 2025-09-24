# update_manifest_and_commit.ps1
# Computes SHA256 for three release artifacts, updates manifest_for_release.json.template,
# commits and pushes the updated manifest.

$RepoPath = (Get-Location).Path
$ManifestPath = Join-Path $RepoPath "manifest_for_release.json.template"
$ReleaseTag = "v1.0"
$ReleaseTitle = "Verifiable Governance for Public Algorithms - Release Candidate v1.0"
$ReleaseDate = (Get-Date).ToString("yyyy-MM-dd")
$Owner = "Jordan Crosno"

$Artifacts = @(
  @{ name = "release_candidate_v1.pdf";  pillars = @("Transparency","Auditability","Due Process"); doi = "doi:10.5281/zenodo.XXXX" },
  @{ name = "starter_pack_v1.zip";       pillars = @("Subsidiarity","Inclusive Deliberation","Fairness"); doi = "" },
  @{ name = "manifest_for_release.json.template"; pillars = @("Auditability","Transparency"); doi = "" }
)

function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK] $m" -ForegroundColor Green }
function Err($m){ Write-Host "[ERR] $m" -ForegroundColor Red }

Set-Location $RepoPath

foreach ($a in $Artifacts) {
  $path = Join-Path $RepoPath $a.name
  if (Test-Path $path) {
    try {
      $h = Get-FileHash -Path $path -Algorithm SHA256
      $a.sha256 = $h.Hash.ToUpper()
      Ok "Hash for $($a.name): $($a.sha256)"
    } catch {
      Err "Failed to compute hash for $($a.name): $($_.Exception.Message)"
      exit 10
    }
  } else {
    Err "File not found: $($a.name). Place the file in $RepoPath and re-run the script."
    exit 11
  }
}

if (Test-Path $ManifestPath) {
  try {
    $raw = Get-Content $ManifestPath -Raw
    $manifest = $raw | ConvertFrom-Json -ErrorAction Stop
    Info "Loaded existing manifest_for_release.json.template"
  } catch {
    Info "Existing manifest not valid JSON; creating new manifest object"
    $manifest = [pscustomobject]@{}
  }
} else {
  Info "No existing manifest found; creating new manifest object"
  $manifest = [pscustomobject]@{}
}

if (-not $manifest.PSObject.Properties.Name -contains "release") {
  $manifest | Add-Member -MemberType NoteProperty -Name release -Value ([pscustomobject]@{ tag=$ReleaseTag; title=$ReleaseTitle; date=$ReleaseDate })
} else {
  $manifest.release.tag = $ReleaseTag
  $manifest.release.title = $ReleaseTitle
  $manifest.release.date = $ReleaseDate
}
if (-not $manifest.PSObject.Properties.Name -contains "artifacts") {
  $manifest | Add-Member -MemberType NoteProperty -Name artifacts -Value @()
}
if (-not $manifest.PSObject.Properties.Name -contains "notes") {
  $manifest | Add-Member -MemberType NoteProperty -Name notes -Value "Fill minted DOI and deposition_url after Zenodo publication. Checksums computed with SHA256."
}

function Upsert-Artifact($manifestObj, $entry) {
  $existing = $manifestObj.artifacts | Where-Object { $_.name -eq $entry.name }
  $prov = @{ deposited_by = $Owner; deposited_date = $ReleaseDate }
  if ($existing) {
    $existing.sha256 = $entry.sha256
    $existing.doi = $entry.doi
    $existing.provenance = $prov
    $existing.pillars = $entry.pillars
    Info "Updated artifact entry: $($entry.name)"
  } else {
    $new = [pscustomobject]@{
      name = $entry.name
      sha256 = $entry.sha256
      doi = $entry.doi
      provenance = $prov
      pillars = $entry.pillars
    }
    $manifestObj.artifacts += $new
    Info "Added artifact entry: $($entry.name)"
  }
}

foreach ($a in $Artifacts) { Upsert-Artifact $manifest $a }

try {
  $manifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $ManifestPath
  Ok "Manifest written to $ManifestPath"
  Get-Item $ManifestPath | Select-Object Name,Length,LastWriteTime | Format-List
} catch {
  Err "Failed to write manifest: $($_.Exception.Message)"
  exit 20
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Err "git not found in PATH. Commit step skipped. Add and commit the manifest manually."
  exit 30
}

try {
  git add --force $ManifestPath
  $commitMessage = "Add checksums, SIDE mapping, and DOI placeholders for $ReleaseTag"
  git commit -m $commitMessage
  git push
  Ok "Manifest committed and pushed. Commit message: $commitMessage"
} catch {
  Err "Git commit/push failed: $($_.Exception.Message)"
  Err "You can run: git add `"$ManifestPath`"; git commit -m `"$commitMessage`"; git push"
  exit 31
}

Ok "Script completed successfully."
exit 0
