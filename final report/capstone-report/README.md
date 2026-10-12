# Capstone report source

This directory is the working report copied from the BUET CSE 450 template and
rewritten for this project. Generated files are isolated in `build/`.

From PowerShell, compile with MiKTeX:

```powershell
.\build-report.ps1
```

The script deliberately runs BibTeX from the source directory before the final
two PDFLaTeX passes. This keeps citations portable while all generated files stay
under `build/`. The PDF will be written to `build/main.pdf`.

If script execution is disabled, run the same commands manually from this
directory:

```powershell
New-Item -ItemType Directory -Force build
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build main.tex
bibtex build/main
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build main.tex
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build main.tex
```

Before submission, search for `TO BE CONFIRMED`, `Draft status`, and
`Drafting note`. Those markers identify facts that the repository does not
establish, including supervisor details, session, submission date, verified
individual contributions, final costs, and several experiment reconciliations.
