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
