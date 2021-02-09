
![Build](https://ci.wertarbyte.com/job/ChunkyCL/lastStableBuild/badge/icon?style=flat-square)

# ChunkyCL

ChunkyCL is a plugin to the Minecraft Pathtracer [Chunky](https://github.com/chunky-dev/chunky) which harnesses the power of the GPU with OpenCL 1.2 to accelerate rendering.
It is currently a work in progress and does not support many features such as non-cube blocks and biome tinting. The core renderer itself is still under development
so render results may change drastically between versions.

## Installation

Download the [latest plugin build](https://discord.com/channels/@me/804323812166074378/808804495206776873). In the Chunky Launcher, expand `Advanced Settings` and click on `Manage plugins`. In the `Plugin Manger` window click on `Add` and select the `.jar` file in the extracted
zip file. Click on `Save` and start Chunky as usual.

### Performance

Rough performance with a RTX 2070 is around 10 times that of the traditional CPU renderer as of 2021-02-02.

Decreasing `Render threads` or `CPU utilization` may improve GPU performance.

## Compatibility

* Not compaitable with the Denoising Plugin.
