# Maintenance cheatsheet (wip)

## Adding new submodules

Required: `--name` option

```
$ git submodule add --name "ORG/REPO" "https://github.com/ORG/REPO.git" "third_party/ORG/REPO"
```

Then edit `.gitmodules` to add `branch` directive

```
[submodule "ORG/REPO"]
	path = third_party/ORG/REPO
	url = https://github.com/ORG/REPO.git
    branch = vMAJOR.MINOR.PATCH
```
