pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Meta Wearables DAT SDK (GitHub Packages)
        maven {
            url = uri("https://maven.pkg.github.com/facebook/meta-wearables-dat-android")
            credentials {
                username = providers.gradleProperty("gpr.user").orElse(
                    providers.environmentVariable("GITHUB_USER")
                ).getOrElse("")
                password = providers.gradleProperty("gpr.token").orElse(
                    providers.environmentVariable("GITHUB_TOKEN")
                ).getOrElse("")
            }
        }
    }
}

rootProject.name = "VisionClaw4Droid"
include(":app")
