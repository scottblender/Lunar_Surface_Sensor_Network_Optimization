# Ava: PowerShell GA location-convergence launcher

Please follow these instructions to set up the repository and write the launcher.
The MATLAB code is provided. Your task is the PowerShell script.

1. Set up Git and the repository

Install Git from https://git-scm.com/downloads/win and accept the collaborator
invitation. Open PowerShell. If this is your first Git setup, run:

```powershell
git config --global user.name "Your Name"
git config --global user.email "your-github-email@example.com"
New-Item -ItemType Directory -Force "$HOME\Documents\MATLAB" | Out-Null
cd "$HOME\Documents\MATLAB"
git clone https://github.com/scottblender/Lunar_Surface_Sensor_Network_Optimization.git
cd Lunar_Surface_Sensor_Network_Optimization
```

2. Work on Ava

After the GA-support PR has been merged into main, update your existing branch:

```powershell
git fetch origin
git switch Ava
git merge origin/main
git branch --show-current
git status
git config --local push.default nothing
```

The branch must say Ava. Start with a clean working tree. If Git reports a merge
conflict, stop and ask Scott rather than resetting files. Always work on Ava.

3. Check MATLAB

Open MATLAB in the repository root and run:

```matlab
setupProject;
addpath("tests/fixtures");
results = runtests("tests/optimization/testGaConvergenceStudy.m");
assertSuccess(results);
```

These tests create their own small database. Full runs need the frozen global
database and its chunk files from Scott; those are not stored in GitHub.
Global Optimization Toolbox is required. Parallel modes also need Parallel
Computing Toolbox.

4. Write the PowerShell script

Create `scripts/batch/run_ga_convergence.ps1`.

Read `docs/ga_convergence_powershell_contract.md` and start from
`config/ga_convergence_request.example.json`.

Your script should collect the database path, output folder, independent-run
counts, FE budgets, population size, base seed, parallel mode and worker limit.
Support validation-only and resume options. Write one UTF-8 JSON request, set
`LUNAR_GA_REQUEST` to its absolute path, and launch MATLAB once from the repository
root using the entry command in the contract. Preserve logs and return an error
if MATLAB fails. Restore the working directory and environment variable afterward.

MATLAB performs the sweep, seed handling, checkpointing and plotting. You do not
need to change the GA adapter, objective or MATLAB driver, or write another
parallel loop. Test only three observers on the global database.
Reuse existing repository helpers wherever possible; do not copy MATLAB logic
into the PowerShell script.

5. Check the script

First check validation-only mode. Then use Scott's database for a small serial
run with two independent runs and budgets divisible by the population size.
Rerun the same request to check that checkpoints are reused. Check paths containing
spaces and a missing database. Compare parallel modes only after the serial case
works, using separate output folders.

Confirm that MATLAB produces the two polar figures: location consistency versus
independent runs, and versus FE budget. The observer coordinate CSV files should
also be present. Example budgets are test settings, not convergence conclusions.

6. Save and submit your work

```powershell
git branch --show-current
git status
git add scripts/batch/run_ga_convergence.ps1
git commit -m "Add PowerShell launcher for GA location convergence"
git push origin Ava
```

Stage any launcher tests you add as well. Open a pull request from Ava into main
for review. Please do not push directly to main. Let Scott know if setup, merging,
MATLAB licensing or database access causes problems.
