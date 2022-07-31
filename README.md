# Patching/updating CRs (pucr) at different versions

This repository includes a comprehensive test plan to illustrate the observed, unanticipated outcomes that occur when patching and/or updating Kubernetes custom resources at different versions.

* [**Test plan**](#test-plan): the test plan
* [**Prerequisites**](#prerequisite): requirements to run the test plan
* [**Getting started**](#getting-started): set up the world
* [**Running the tests**](#running-the-tests): executing the test plan
* [**Conclusion**](#conclusion): the results of the executed test plan

## Test plan

Lorem ipsum.

## Prerequisites

The following requirements are necessary to run the examples in the test plan:

* Docker 20.10+
* GNU Make 4.2+

## Getting started

1. Build the docker image locally:

    ```shell
    make image-build
    ```

1. Run the docker image:

    ---

    **Please note** the container runs with elevated privileges to bind mount the host's docker socket in order to support running Kind from within the container.

    ---

    ```shell
    make image-run
    ```

## Running the tests

Lorem ipsum.

## Conclusion

Lorem ipsum.
