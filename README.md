# Eclipse JKube Images

This repository hosts part of the container images used by [Eclipse JKube](https://github.com/eclipse/jkube).

These images are available on [Quay.io](https://quay.io/organization/jkube)

## Available images

### jkube-java

https://quay.io/repository/jkube/jkube-java

Base image to be used by any `JavaExecGenerator` implementation. The image is based on
[ubi8/openjdk-11](https://github.com/jboss-container-images/openjdk/blob/d5ed2f4e811861ab921a33004da37de13f67f0ba/ubi8-openjdk-11.yaml#L6)
([catalog.redhat.com](https://catalog.redhat.com/software/containers/detail/5dd6a4b45a13461646f677f4?container-tabs=overview))
with stripped down dependencies to make it lighter.

The image contains the `run-java.sh` script added by
[jboss.container.java.run.bash](https://github.com/jboss-openshift/cct_module/blob/d6beef5d576459fcc80358f09f2ab20886dad0df/jboss/container/java/run/bash/module.yaml#L2)
module.

Available environment variables for runtime configuration:
- **`JAVA_APP_DIR`** The directory where the application resides. All paths in your application are relative to this
  directory.
- **`JAVA_LIB_DIR`** Directory holding the Java jar files as well an optional `classpath` file which holds the classpath.
  Either as a single line classpath (colon separated) or with jar files listed line-by-line. If not set **JAVA_LIB_DIR**
  is the same as **`JAVA_APP_DIR`**.
- **`JAVA_OPTIONS`** JVM options passed to the `java` command.  Use **`JAVA_OPTIONS`**.
- **`JAVA_OPTS`** JVM options passed to the `java` command.
* **`JAVA_INITIAL_MEM_RATIO`** Is used when no `-Xms` option is given in **`JAVA_OPTIONS`**. This is used to calculate a
  default initial heap memory based on the maximum heap memory. If used in a container without any memory constraints
  for the container then this option has no effect. If there is a memory constraint then `-Xms` is set to a ratio of
  the `-Xmx` memory as set here. The default is `25` which means 25% of the `-Xmx` is used as the initial heap size.
  You can skip this mechanism by setting this value to `0` in which case no `-Xms` option is added.
* **`JAVA_MAX_MEM_RATIO`** Is used when no `-Xmx` option is given in **`JAVA_OPTIONS`**. This is used to calculate a default
  maximal heap memory based on a containers restriction. If used in a container without any memory constraints for the
  container then this option has no effect. If there is a memory constraint then `-Xmx` is set to a ratio of the
  container available memory as set here. The default is `50` which means 50% of the available memory is used as an upper
  boundary. You can skip this mechanism by setting this value to `0` in which case no `-Xmx` option is added.
* **`JAVA_DIAGNOSTICS`** Set this to get some diagnostics information to standard output when things are happening.
  **Disabled by default.**
* **`JAVA_MAIN_CLASS`** A main class to use as argument for `java`. When this environment variable is given, all jar
  files in **`JAVA_APP_DIR`** are added to the classpath as well as **`JAVA_LIB_DIR`**.
* **`JAVA_APP_JAR`** A jar file with an appropriate manifest so that it can be started with `java -jar` if no
  `$JAVA_MAIN_CLASS` is set. In all cases this jar file is added to the classpath, too.
* **`JAVA_APP_NAME`** Name to use for the process.
* **`JAVA_CLASSPATH`** The classpath to use. If not given, the startup script checks for a file
  `**JAVA_APP_DIR/classpath**` and use its content literally as classpath. If this file doesn't exist all jars in the
  app dir are added (`classes:**JAVA_APP_DIR/***`).
* **`JAVA_DEBUG`** If set remote debugging will be switched on. **Disabled by default.**
* **`JAVA_DEBUG_SUSPEND`** If set enables suspend mode in remote debugging
* **`JAVA_DEBUG_PORT`** Port used for remote debugging. Defaults to *5005*.
* **`HTTP_PROXY`** The location of the http proxy. This takes precedence over **`http_proxy`**, and
  will be used for both Maven builds and Java runtime.
* **`HTTPS_PROXY`** The location of the https proxy. This takes precedence over **`http_proxy`** and **`HTTP_PROXY`**,
* and will be used for both Maven builds and Java runtime.
* **`no_proxy`** / **`NO_PROXY`** A comma separated lists of hosts, IP addresses or domains that can be accessed directly.
  This will be used for both Maven builds and Java runtime.
* **`AB_PROMETHEUS_OFF`** Disables the use of Prometheus Java Agent.
* **`AB_PROMETHEUS_PORT`** Port to use for the Prometheus JMX Exporter.

### jkube-remote-dev

https://quay.io/repository/jkube/jkube-remote-dev

Base image to be used by Eclipse JKube's remote development service.

### jkube-tomcat

https://quay.io/repository/jkube/jkube-tomcat

Base image to be used by any `WebAppGenerator` & `TomcatAppSeverHandler` implementation.

### jkube-tomcat9

https://quay.io/repository/jkube/jkube-tomcat9

Base image to be used by any `WebAppGenerator` & `TomcatAppSeverHandler` implementation relying on Tomcat 9.

### jkube-jetty9

https://quay.io/repository/jkube/jkube-jetty9

Base image to be used by any `WebAppGenerator` & `JettyAppSeverHandler` implementation.

### jkube-karaf

https://quay.io/repository/jkube/jkube-karaf

Base image to be used by `KarafGenerator`.
