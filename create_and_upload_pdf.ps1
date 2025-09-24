<#
create_and_upload_pdf.ps1
Creates a simple release_candidate_v1.pdf (Word COM if available, otherwise wkhtmltopdf HTML fallback),
verifies the file, and uploads it to the existing GitHub release tag v1.0 using gh.

Usage:
  Save file in repo root and run:
    .\create_and_upload_pdf.ps1

Edit variables below if you need a different release tag or repo name.
#>

# ----- Configuration -----
$ReleaseTag = "v1.0"
$Repo = "jordancrosno/Attempt1"
$PdfName = "release_candidate_v1.pdf"
$HtmlStub = "release_stub.html"
$VerbosePreference = "Continue"

# ----- Helper functions -----
function Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Success($msg){ Write-Host "[OK]   $msg" -ForegroundColor Green }
function ErrorMsg($msg){ Write-Host "[ERR]  $msg" -ForegroundColor Red }

# ----- Step 1: If the PDF already exists, skip creation -----
if (Test-Path -Path ".\$PdfName") {
    Info "PDF already exists: .\$PdfName"
    Get-Item .\$PdfName | Select-Object Name,Length,LastWriteTime | Format-List
} else {
    # ----- Attempt A: Create using Word COM automation (if available) -----
    $created = $false
    try {
        Info "Trying Word COM automation..."
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $word.Visible = $false
        $doc = $word.Documents.Add()
        $sel = $word.Selection
        $sel.TypeText("Release candidate v1.0`r`nVerifiable Governance for Public Algorithms`r`nJordan Crosno`r`nSeptember 2025")
        $outPath = Join-Path (Get-Location) $PdfName
        # Use ExportAsFixedFormat to avoid SaveAs type conversion issues
        $doc.ExportAsFixedFormat($outPath, 17)
        $doc.Close()
        $word.Quit()
        $created = Test-Path -Path ".\$PdfName"
        if ($created) { Success "PDF created via Word COM: .\$PdfName" }
    } catch {
        ErrorMsg "Word COM automation failed or Word not available. Exception: $($_.Exception.Message)"
        try { if ($doc -ne $null) { $doc.Close() } } catch {}
        try { if ($word -ne $null) { $word.Quit() } } catch {}
    }

    # ----- Attempt B: wkhtmltopdf HTML -> PDF fallback -----
    if (-not $created) {
        Info "Checking for wkhtmltopdf in PATH..."
        $wk = Get-Command wkhtmltopdf -ErrorAction SilentlyContinue
        if ($wk) {
            Info "wkhtmltopdf found: $($wk.Path). Creating HTML stub and converting..."
            @'
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Release candidate v1.0</title></head>
  <body style="font-family: Arial, sans-serif; margin: 2em;">
    <h1>Release candidate v1.0</h1>
    <p><strong>Verifiable Governance for Public Algorithms</strong></p>
    <p>Jordan Crosno — September 2025</p>
  </body>
</html>
'@ | Out-File -Encoding UTF8 $HtmlStub
            & wkhtmltopdf $HtmlStub $PdfName
            $created = Test-Path -Path ".\$PdfName"
            if ($created) { Success "PDF created via wkhtmltopdf: .\$PdfName" } else { ErrorMsg "wkhtmltopdf ran but PDF not created." }
        } else {
            ErrorMsg "wkhtmltopdf not found in PATH."
        }
    }

    # ----- Attempt C: pandoc (markdown -> pdf) fallback -----
    if (-not $created) {
        Info "Checking for pandoc in PATH..."
        $pn = Get-Command pandoc -ErrorAction SilentlyContinue
        if ($pn) {
            Info "pandoc found. Creating minimal markdown and converting..."
            $md = "release_stub.md"
            @'
# Release candidate v1.0

**Verifiable Governance for Public Algorithms**

Jordan Crosno — September 2025
'@ | Out-File -Encoding UTF8 $md
            & pandoc $md -o $PdfName
            $created = Test-Path -Path ".\$PdfName"
            if ($created) { Success "PDF created via pandoc: .\$PdfName" } else { ErrorMsg "pandoc ran but PDF not created." }
        } else {
            ErrorMsg "pandoc not found in PATH."
        }
    }

    # ----- Final failure message if none worked -----
    if (-not $created) {
        ErrorMsg "Unable to create PDF with available tools. Options:"
        Write-Host " - Install Microsoft Word and retry the script, or" -ForegroundColor Yellow
        Write-Host " - Install wkhtmltopdf and retry, or" -ForegroundColor Yellow
        Write-Host " - Install pandoc and LaTeX toolchain for PDF output and retry." -ForegroundColor Yellow
        exit 2
    }
}

# ----- Step 2: Show resulting file info -----
$info = Get-Item .\$PdfName -ErrorAction SilentlyContinue
if (-not $info) {
    ErrorMsg "Expected PDF not found after creation steps."
    exit 3
}
$info | Select-Object Name,Length,LastWriteTime | Format-List

# ----- Step 3: Upload to GitHub release using gh -----
Info "Uploading $PdfName to release $ReleaseTag in repo $Repo..."
try {
    $upload = gh release upload $ReleaseTag ".\$PdfName" --repo $Repo 2>&1
    if ($LASTEXITCODE -eq 0) {
        Success "Upload succeeded."
        Write-Host $upload
    } else {
        ErrorMsg "gh returned non-zero exit code. Output:"
        Write-Host $upload
        exit 4
    }
} catch {
    ErrorMsg "Exception while calling gh: $($_.Exception.Message)"
    exit 5
}

# ----- Done -----
Success "Script completed."
exit 0