allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 빌드 출력을 프로젝트 루트의 build/ 로 둔다 (Flutter 표준).
// ASCII·비-OneDrive 경로(C:\dev\lmpm)에서 작업하므로 별도 리다이렉트 불필요.
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
