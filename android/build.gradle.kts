allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 빌드 출력을 OneDrive 밖 + ASCII 경로로 둔다. OneDrive 파일 잠금과
// 한글 경로에서의 AAPT2 데몬 실패를 동시에 피하기 위함.
val sharedBuildRoot = rootProject.file("C:/lufs_build")
rootProject.layout.buildDirectory.set(sharedBuildRoot)

subprojects {
    project.layout.buildDirectory.set(java.io.File(sharedBuildRoot, project.name))
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
