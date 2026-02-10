# Opal scripts


## opalPullAllRepos

Pulls all required repositories that you do not currently have checked out into the same directory as opal-shared-infrastructure. This includes:
- opal-shared-infrastructure
- opal-fines-service
- opal-user-service
- opal-logging-service

## opalBuild

Builds the Opal docker stack from the directory opal-shared-infrastructure is stored in.

It defaults to using
`-localBranches`, which fetches/pulls the current branch in each repo, runs Gradle builds, and then
builds and starts the containers. Use `-localMaster` (`-lm`) to checkout `master` first. Use
`-c`/`--current` to skip git updates and Gradle builds.

Examples:

```
./scripts/opalBuild.sh
./scripts/opalBuild.sh -lb
./scripts/opalBuild.sh -lm
./scripts/opalBuild.sh -c
```

## opalDown

Stops the docker stack and optionally removes volumes.

Examples:

```
./scripts/opalDown.sh
./scripts/opalDown.sh -r
```

## Install as commands
If you would like to be able to run these commands from any terminal, you can do the following.

Identify your project structure / the path to your projects
```bash
pwd
```
For me this outputs `/Users/cadefaulkner/opal/opal-shared-infrastructure/docker-files-scripts`
the part of interest is `/Users/cadefaulkner/opal`
yours may be `/Users/youruser/documents/opal` this is what you will define as your `BASE_DIR`.
---
Define your `BASE_DIR` as a variable accessible in your environment.

For Bash
```
echo 'export BASE_DIR=/Users/youruser/opal' >> ~/.bashrc
```
For Zsh (default mac terminal)
```
echo 'export BASE_DIR=/Users/youruser/opal' >> ~/.zshrc
```
Then reload (you can also close and re-open the terminal)
```zsh
source ~/.zshrc   # or ~/.bashrc
```
---
Run this command, it will make the files in `~/bin` available to your terminal.
```
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
```

The following will ensure `~/bin` exists and install the scripts to that location.
```bash
mkdir -p "$HOME/bin"

install -m 755 ./opalBuild.sh "$HOME/bin/opalBuild"
install -m 755 ./opalDown.sh  "$HOME/bin/opalDown"
```
---
The scripts can now be used from any terminal.

Examples:
```
opalBuild
opalBuild -lb
opalBuild -lm
opalBuild -c

opalDown
opalDown -r
```