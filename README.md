# Mirror script for *.release.flatcar-linux.net

This script mirrors the Flatcar release server to the current directory.
It creates a subfolder per release channel and updates its contents when rerun.

The folder for [stable.release.flatcar-linux.net](https://stable.release.flatcar-linux.net/)
will be called `stable`, and the same applies to `alpha`, `beta`, and `edge`.

Files are only created and never deleted. Files per release channel are downloaded
sequential, but all release channels are downloaded in parallel.

It supports flags to filter limit the downloading to new releases
or to exclude certain image files by pattern. A detailed log can be enabled.

```
Usage:
--above-version VERSION    Skip folders which have versions that are lower than VERSION (e.g., 2000)
--not-files FILTER         Skip files/folders with certain patterns by running
                           grep -v 'FILTER' on the list of './NAME' entries
                           (e.g., 'vmware\|virtualbox')
--only-files FILTER        Mirror files only with certain patterns by running
                           grep 'FILTER' on the list of './NAME' entries
                           (e.g., 'vmware\|virtualbox')
  NOTE: Only one of two options, --not-files and --only-files, should be used.
--logfile FILE             Write detailed log to FILE (can also be /dev/stderr)
--channels CHANNELS        Coma-separated list of channels to mirror (e.g. stable,beta).
                           By default all channels are mirrored.
--arch ARCH                Filter the only architecture to download (either amd64 or arm64).
--help                     Show flags
```
