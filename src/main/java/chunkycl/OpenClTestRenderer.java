package chunkycl;

import static org.jocl.CL.*;

import chunkycl.renderer.RendererInstance;
import chunkycl.renderer.scene.*;
import org.jocl.*;

import se.llbit.chunky.main.Chunky;
import se.llbit.chunky.renderer.DefaultRenderManager;
import se.llbit.chunky.renderer.Renderer;
import se.llbit.chunky.renderer.ResetReason;
import se.llbit.log.Log;
import se.llbit.math.Octree;
import se.llbit.math.PackedOctree;

import java.util.Arrays;
import java.util.function.BooleanSupplier;

public class OpenClTestRenderer implements Renderer {

    private BooleanSupplier postRender = () -> true;

    @Override
    public String getId() {
        return "ChunkyClTestRenderer";
    }

    @Override
    public String getName() {
        return "ChunkyClTestRenderer";
    }

    @Override
    public String getDescription() {
        return "ChunkyClTestRenderer";
    }

    @Override
    public void setPostRender(BooleanSupplier callback) {
        postRender = callback;
    }

    @Override
    public void render(DefaultRenderManager manager) throws InterruptedException {
        ClOctree octree;

        RendererInstance instance = RendererInstance.get();
        double[] sampleBuffer = manager.bufferedScene.getSampleBuffer();
        float[] passBuffer = new float[sampleBuffer.length];

        ClTextureAtlas.AtlasBuilder atlasBuilder = new ClTextureAtlas.AtlasBuilder();
        ClBlockPalette.preLoad(manager.bufferedScene.getPalette(), atlasBuilder);

        ClTextureAtlas atlas = atlasBuilder.build();
        atlasBuilder.release();

        ClBlockPalette palette = new ClBlockPalette(manager.bufferedScene.getPalette(), atlas);

        Octree.OctreeImplementation sceneOctree = manager.bufferedScene.getWorldOctree().getImplementation();
        if (sceneOctree instanceof PackedOctree) {
            octree = new ClOctree((PackedOctree) sceneOctree);
        } else {
            Log.error("Only PackedOctree is supported.");
            return;
        }

        ClCamera camera = new ClCamera(manager.bufferedScene);
        camera.generate();


        cl_mem buffer = clCreateBuffer(instance.context, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
                (long) Sizeof.cl_float * passBuffer.length, Pointer.to(passBuffer), null);
        cl_kernel kernel = clCreateKernel(instance.program, "render", null);

        clSetKernelArg(kernel, 0, Sizeof.cl_mem, Pointer.to(camera.rayPos));
        clSetKernelArg(kernel, 1, Sizeof.cl_mem, Pointer.to(camera.rayDir));
        clSetKernelArg(kernel, 2, Sizeof.cl_mem, Pointer.to(octree.octreeDepth));
        clSetKernelArg(kernel, 3, Sizeof.cl_mem, Pointer.to(octree.octreeData));
        clSetKernelArg(kernel, 4, Sizeof.cl_mem, Pointer.to(palette.blocks));
        clSetKernelArg(kernel, 5, Sizeof.cl_mem, Pointer.to(atlas.texture));
        clSetKernelArg(kernel, 6, Sizeof.cl_mem, Pointer.to(buffer));
        clEnqueueNDRangeKernel(instance.commandQueue, kernel, 1, null,
                new long[] {passBuffer.length / 3}, null, 0, null, null);
        clEnqueueReadBuffer(instance.commandQueue, buffer, CL_TRUE, 0,
                (long) Sizeof.cl_float * passBuffer.length, Pointer.to(passBuffer),
                0, null, null);

        Chunky.getCommonThreads().submit(() -> Arrays.parallelSetAll(sampleBuffer, i -> passBuffer[i])).join();

        postRender.getAsBoolean();

        atlas.release();
        octree.release();
        palette.release();
        camera.release();
        clReleaseMemObject(buffer);
    }
}
