$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Push-Location -LiteralPath $PSScriptRoot
try {
    New-Item -ItemType Directory -Force -Path 'build' | Out-Null

    & pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build main.tex
    if ($LASTEXITCODE -ne 0) { throw "The first PDFLaTeX pass failed with exit code $LASTEXITCODE." }

    & bibtex build/main
    if ($LASTEXITCODE -ne 0) { throw "BibTeX failed with exit code $LASTEXITCODE." }

    & pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build main.tex
    if ($LASTEXITCODE -ne 0) { throw "The second PDFLaTeX pass failed with exit code $LASTEXITCODE." }

    & pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build main.tex
    if ($LASTEXITCODE -ne 0) { throw "The final PDFLaTeX pass failed with exit code $LASTEXITCODE." }

    Write-Host "Report compiled successfully: $PSScriptRoot\build\main.pdf"
}
finally {
    Pop-Location
}

