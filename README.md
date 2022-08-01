# Patching/updating CRs (pucr) at different versions

This repository includes a comprehensive test plan to illustrate the observed, unanticipated outcomes that occur when patching and/or updating Kubernetes custom resources at different versions.

* [**Test plan**](#test-plan): the test plan
* [**Prerequisites**](#prerequisites): requirements to run the test plan
* [**Getting started**](#getting-started): set up the world
* [**Running the tests**](#running-the-tests): executing the test plan
* [**Conclusion**](#conclusion): the results of the executed test plan

## Test plan

| client | op | server-side apply | preserve unknown fields | conversion webhook | pre-op state of resource| post-op state of resource |
|---|---|---|---|---|---|---|
| `kubectl`  | apply | false | false | false | `404`  |   |
|            | apply | true  | false | false | `404`  |   |

* client variations
  * kubectl `--server-side=true`
  * kubectl `--server-side=false`
  * curl
  * client-go typed
  * client-go unstructured
* `x-kubernetes-preserve-unknown-fields`
  * true
  * false
* conversion webhook
  * installed
  * uninstalled
* pre-op state
  * created
  * updated
  * patched
* op
  * create
  * update
  * patch
  * get

## Prerequisites

It is strongly advised to run the test plan within the provided, Docker container to simplify matters:

### In a Docker container

* **Software**
  * [Docker](https://docs.docker.com/get-docker/) 20.10+
  * [GNU Make](https://www.gnu.org/software/make/) 4.2+

### On the local host

However, it is also possible to run the test plan directly provided the following software is available:

* [Docker](https://docs.docker.com/get-docker/) 20.10+
* [GNU Make](https://www.gnu.org/software/make/) 4.2+
  * macOS ships with GNU Make ~3.81, which does not include support for the `file` function used by this project's `Makefile`. Please use homebrew and `brew install make` to install GNU Make 4.2+.
* [jq](https://stedolan.github.io/jq/) 1.6=
* [kind](https://kind.sigs.k8s.io) 0.11.1+
* [OpenSSL](https://www.openssl.org) 3+
  * macOS ships with LibreSSL ~2.8.3, which does not include the `-addext` flag used by this project to generate a self-signed certificate. Please use homebrew and `brew install openssl` to install OpenSSL 3+.
* [yq](https://mikefarah.gitbook.io/yq/) 4.26.1+

## Getting started

1. Build the docker image locally:

    ```shell
    make image-build
    ```

1. Run the docker image:

    ---

    :warning: Please note that the image must be run with elevated privileges in order to bind mount the host's docker socket into the container to support running Kind from within the container.

    ---

    ```shell
    make image-run
    ```

## Running the tests

Lorem ipsum.

## Conclusion

Lorem ipsum.
