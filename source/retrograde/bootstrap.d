/**
 * Retrograde Engine
 *
 * Authors:
 *  Mike Bierlee, m.bierlee@lostmoment.com
 * Copyright: 2014-2023 Mike Bierlee
 * License:
 *  This software is licensed under the terms of the MIT license.
 *  The full terms of the license can be found in the LICENSE.txt file.
 */

module retrograde.bootstrap;

import retrograde.core.runtime : EngineRuntime, StandardEngineRuntime;
import retrograde.core.game : Game;
import retrograde.core.entity : EntityManager;
import retrograde.core.messaging : MessageHandler;
import retrograde.core.platform : Platform, PlatformSettings, NullPlatform;
import retrograde.core.logging : StdoutLogger;
import retrograde.core.input : InputMapper;
import retrograde.core.rendering : RenderSystem, ShaderProgram, GraphicsApi, NullGraphicsApi, DepthTestingMode;
import retrograde.core.storage : StorageSystem, GenericStorageSystem;

import retrograde.rendering.generic : GenericRenderSystem;

import retrograde.ai.generative.stabilityai : StabilityAiApi, StabilityAiApiImpl;

import poodinis : Inject, DependencyContainer, ResolveOption, initializedBy, existingInstance;
import poodinis.valueinjector.mirage : loadConfig, parseIniConfig;

import std.logger : Logger, MultiLogger, sharedLog;
import std.file : exists;

struct GraphicsApiSettings {
    /*
     * Set the initial depth testing mode.
     * Setting it up in the bootstrap prevents unnecesary recompilation of shaders.
     */
    DepthTestingMode initialDepthTestingMode = DepthTestingMode.apiDefault;

    //TODO: Add more settings?
}

version (Have_glfw_d) {
    import retrograde.platform.glfw : GlfwPlatform, GlfwPlatformSettings;

    alias DefaultPlatform = GlfwPlatform;
    alias DefaultPlatformSettings = GlfwPlatformSettings;
} else {
    alias DefaultPlatform = NullPlatform;
    alias DefaultPlatformSettings = PlatformSettings;
}

version (Have_bindbc_opengl) {
    import retrograde.rendering.api.opengl : OpenGlGraphicsApi;

    alias DefaultGraphicsApi = OpenGlGraphicsApi;
} else {
    alias DefaultGraphicsApi = NullGraphicsApi;
}

/**
 * Bootstrap function for quickly setting up the DI framework with all required and typically
 * used engine functionality. After set-up, the game is started.
 */
public void startGame(GameType : Game, EngineRuntimeType:
    EngineRuntime = StandardEngineRuntime, PlatformType:
    Platform = DefaultPlatform,
RenderSystemType:
    RenderSystem = GenericRenderSystem,
GraphicsApiType:
    GraphicsApi = DefaultGraphicsApi)(
    const PlatformSettings platformSettings = new DefaultPlatformSettings(),
    const GraphicsApiSettings graphicsApiSettings = GraphicsApiSettings(),
    shared DependencyContainer dependencies = new shared DependencyContainer(),
    const bool suppressBootstrapWarnings = false
) {

    dependencies.setPersistentResolveOptions(ResolveOption.registerBeforeResolving);

    dependencies.register!(EngineRuntime, EngineRuntimeType);
    dependencies.register!(Game, GameType);
    dependencies.register!(RenderSystem, RenderSystemType);
    dependencies.register!(GraphicsApi, GraphicsApiType);
    dependencies.register!(Platform, PlatformType);
    dependencies.register!(StorageSystem, GenericStorageSystem);
    dependencies.register!(StabilityAiApi, StabilityAiApiImpl);

    const configPath = "./engine.ini";
    if (exists(configPath)) {
        dependencies.loadConfig(configPath);
    } else {
        string defaultConfig = import(configPath);
        dependencies.parseIniConfig(defaultConfig);
    }

    dependencies.register!Logger.initializedBy({
        auto logger = new MultiLogger(); // Cannot be shared, but must be for sharedLog

        auto stdoutLogger = new StdoutLogger();
        if (stdoutLogger.stdoutIsAvailable()) {
            logger.insertLogger("stdoutLogger", stdoutLogger);
        }

        // sharedLog = stdoutLogger; //Creating shared loggers is broken. Fix when phobos fixes it.
        return logger;
    });

    static if (is(DefaultPlatform == NullPlatform)) {
        if (!suppressBootstrapWarnings) {
            dependencies.resolve!Logger.warning(
                "No platform implementation available. Using NullPlatform. Add a suitable platform library to your project to get rid of this warning."
            );
        }
    }

    static if (is(DefaultGraphicsApi == NullGraphicsApi)) {
        if (!suppressBootstrapWarnings) {
            dependencies.resolve!Logger.warning(
                "No graphics api implementation available. Using NullGraphicsApi. Add a suitable graphics api library to your project to get rid of this warning."
            );
        }
    }

    auto graphicsApi = dependencies.resolve!GraphicsApi;
    graphicsApi.setDepthTestingMode(graphicsApiSettings.initialDepthTestingMode);

    auto renderSystem = dependencies.resolve!RenderSystem;
    auto entityManager = dependencies.resolve!EntityManager;
    entityManager.addEntityProcessor(renderSystem);

    auto runtime = dependencies.resolve!EngineRuntime;
    runtime.startGame(platformSettings);
}

/** 
 * An implementation of the Game interface that contains the usual engine functionality.
 *
 * A bootstrap game takes care of initializing, updating and rendering an EntityManager,
 * MessageHandler and InputMapper. Make sure to call super.X() when overriding any of the Game 
 * interface methods.
 */
class BootstrapGame : Game {
    protected @Inject EntityManager entityManager;
    protected @Inject MessageHandler messageHandler;
    protected @Inject InputMapper inputMapper;

    public void initialize() {
    }

    public void update() {
        messageHandler.shiftStandbyToActiveQueue();
        inputMapper.update();
        entityManager.update();
    }

    public void render(double extraPolation) {
        entityManager.draw();
    }

    public void terminate() {
    }
}

version (unittest) {
    class TestGame : Game {
        public bool isInitialized;

        @Inject private EngineRuntime runtime;
        @Inject EntityManager entityManager;
        @Inject MessageHandler messageHandler;

        public override void initialize() {
            isInitialized = true;
        }

        public override void update() {
            runtime.terminate();
        }

        public override void render(double extraPolation) {
        }

        public override void terminate() {
        }
    }

    @("Bootstrap of testgame")
    unittest {
        auto dependencies = new shared DependencyContainer();
        startGame!TestGame(new PlatformSettings(), GraphicsApiSettings(), dependencies, true);
        const game = dependencies.resolve!TestGame;
        assert(game.isInitialized);
    }
}
