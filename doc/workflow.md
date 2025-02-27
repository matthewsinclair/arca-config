# Systematic Wrap-up and Commit Workflow

This document outlines a structured approach to completing development tasks and systematically committing changes to the repository.

## Automated Workflow Script

The `./scripts/wrap-up` script automates this workflow for you. Run it after completing a feature or bug fix to guide you through the following steps:

## Step 1: Review All Changes

- Use `git status` to check which files have been modified
- Use `git diff` to inspect the actual code changes
- Ensure all changes are consistent, aligned with project goals, and complete
- Check for unintended changes or debugging code that should be removed

## Step 2: Update Documentation

- Update relevant documentation files to reflect your changes
- Consider updating these files:
  - `README.md` for user-facing changes
  - `doc/*.md` files for architectural or design changes
- Add or update usage examples
- Ensure documentation is clear and matches the code changes

## Step 3: Update the Project Journal

- Add a new entry at the top of `doc/arca_config_journal.md`
- Format the entry with the current date (YYYYMMDD)
- Provide a concise summary of changes
- Add bullet points categorizing changes:
  - **Added:** New features or capabilities
  - **Fixed:** Bug fixes or corrections
  - **Improved:** Enhancements to existing functionality
  - **Changed:** Modifications to existing behavior
- The workflow automatically adds the commit information

## Step 4: Final Validation

- Run tests to ensure nothing broke: `./scripts/test`
- Run formatter: `mix format`
- Check for any warnings or errors
- Perform a final review of changes

## Step 5: Commit Changes

- Add all relevant files to staging
- Write a descriptive commit message following the project's conventions
  - Start with a verb (Add, Fix, Update, Improve, etc.)
  - Be specific about what changed
  - Keep the first line under 50 characters
  - Add details in the commit body if needed
- Push changes to the remote repository

## Using This Workflow

The benefits of this systematic approach include:

1. **Consistency:** Ensures all necessary steps are completed before committing
2. **Documentation:** Keeps documentation in sync with code changes
3. **Historical record:** Maintains a detailed development journal
4. **Quality:** Enforces testing and validation before commits
5. **Clarity:** Provides clear commit messages

Follow this workflow for all significant changes to maintain high-quality contributions and comprehensive documentation.