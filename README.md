# Patching/updating CRs (pucr) at different versions

This repository provides examples for the observed, unanticipated outcomes when patching and/or updating a custom resource at an older schema version that does not include newer fields for existing types. Values for these fields may be dropped, even when `x-kubernetes-preserve-unknown-fields: true` is enabled, depending on the client.

**What happened:**

Patching and/or updating a custom resource at schema version `N-1` can erase the values of fields defined at version `N` (or subsequent versions) of the API depending on the client used and/or the presence of `x-kubernetes-preserve-unknown-fields: true` in the schema.

**What you expected to happen:**

Patching and/or updating a resource at schema version `N-1` should _not_ erase the values of fields defined at version `N` (or subsequent versions) of the API, _regardless of the client used or the presence of `x-kubernetes-preserve-unknown-fields: true`_.

**How to reproduce it (as minimally and precisely as possible):**

There are two ways to reproduce the issue:

1. **Docker-in-docker** via the [`Dockerfile`](https://github.com/akutz/pucr/blob/main/Dockerfile) from [akutz/pucr](https://github.com/akutz/pucr)
1. **Natively** on the localhost

Reproducing this issue utilizes the following software:

* **Docker-in-docker**
  * [Docker](https://docs.docker.com/get-docker/) 20.10+
  * [git](https://git-scm.com/downloads) 2.32+
* **Natively**
  * [Docker](https://docs.docker.com/get-docker/) 20.10+
  * [GNU Make](https://www.gnu.org/software/make/) 4.2+
    * macOS ships with GNU Make ~3.81, which does not include support for the `file` function used by this project's `Makefile`. Please use homebrew and `brew install make` to install GNU Make 4.2+.
  * [Golang](https://go.dev/dl/) 1.18+
  * [jq](https://stedolan.github.io/jq/) 1.6+
  * [kind](https://kind.sigs.k8s.io) 0.11.1+
  * [kubectl](https://kubernetes.io/docs/tasks/tools/) 1.24+
  * [OpenSSL](https://www.openssl.org) 3+
    * macOS ships with LibreSSL ~2.8.3, which does not include the `-addext` flag used by this project to generate a self-signed certificate. Please use homebrew and `brew install openssl` to install OpenSSL 3+.
  * [yq](https://mikefarah.gitbook.io/yq/) 4.26.1+

Due to the software requirements it is much easier to reproduce the issue using the Docker-in-docker method, but either way works. After the first step, creating the Kubernetes cluster with `kind`, the rest of the instructions are the same, regardless of the reproduction method selected.

1. Create a Kubernetes cluster using `kind`:

    ---

    :sparkle: For this step please select either the **Docker-in-docker** or **Natively** option for creating the Kubernetes cluster. Once the cluster is up, all the remaining steps are the same no matter the method.

    ---

    * **Docker-in-docker**

        1. Clone the repository:

            ```shell
            git clone https://github.com/akutz/pucr
            ```
    
        1. Change directories into the newly cloned repo:

            ```shell
            cd pucr
            ```

        1. Build the container image:

            ```shell
            docker build -t pucr .
            ```

        1. Kind automatically creates a new Docker network named `kind` if one does not exist. This step creates the network in advance in order to ensure the container built in the previous step can be on the same network as the Kind cluster's control plane node:

            ```shell
            [ -n "$(docker network ls -qf 'name=kind')" ] || docker network create kind
            ```

        1. Start the container in privileged mode to mount the Docker socket file into the container in order to allow `kind` to use the host's Docker server from within the container:

            ```shell
            docker run \
              -it \
              --rm \
              --network kind \
              --privileged \
              -v /var/run/docker.sock:/var/run/docker.sock \
              pucr
            ```

        1. Use `kind` inside the container to launch a new Kubernetes cluster:

            ```shell
            kind create cluster --name pucr
            ```

        1. When `kind` creates a cluster, the file `${HOME}/.kube/config` is updated with the cluster's access information. However, the IP address in the cluster's API endpoint will be `127.0.0.1`, which is not the IP on which the API server is running when accessed from within the container. The following command updates the kubeconfig to use the control plane node's IP address on the Docker network:

            ```shell
            kubectl config set-cluster kind-pucr \
              --server="https://$(docker inspect -f \
              '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
              pucr-control-plane):6443"
            ```

    * **Natively**

        1. Use `kind` to create a new Kubernetes cluster:

            ```shell
            kind create cluster --name pucr
            ```

1. Save the access information into files that can be used later by `curl` to interact with the Kubernetes cluster:

    1. Save the API endpoint:

        ```shell
        kubectl config view --raw \
          -o jsonpath='{.clusters[?(@.name == "kind-pucr")].cluster.server}' \
          >url.txt
        ```

    1. Save the cluster's certification authority (CA):

        ```shell
        kubectl config view --raw \
          -o jsonpath='{.clusters[?(@.name == "kind-pucr")].cluster.certificate-authority-data}' | \
          { base64 -d 2>/dev/null || base64 -D; } \
          >ca.crt
        ```

    1. Save the client's public certificate:

        ```shell
        kubectl config view --raw \
          -o jsonpath='{.users[?(@.name == "kind-pucr")].user.client-certificate-data}' | \
          { base64 -d 2>/dev/null || base64 -D; } \
          >client.crt
        ```

    1. Save the client's private key:

        ```shell
        kubectl config view --raw \
          -o jsonpath='{.users[?(@.name == "kind-pucr")].user.client-key-data}' | \
          { base64 -d 2>/dev/null || base64 -D; } \
          >client.key
        ```

    1. Verify the information works by using `curl` to get the `default` namespace:

        ```shell
        curl --cacert ca.crt --cert client.crt --key client.key \
             --silent --show-error \
             -XGET -H 'Accept: application/json' \
             "$(cat url.txt)/api/v1/namespaces/default" | yq -Poyaml
        ```

        If everything worked correctly then the above command _should_ print the YAML for the `default` namespace.

1. Install the `tasks.akutz.github.com` CRD:

    ---

    :sparkle: **Please note** the CRD is installed with `x-kubernetes-preserve-unknown-fields: true` enabled for the `spec` property of the `v1alpha1` version of the `tasks` schema.

    ---

    ```shell
    cat <<EOF | kubectl apply -f -
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: tasks.akutz.github.com
    spec:
      group: akutz.github.com
      names:
        kind: Task
        listKind: TaskList
        plural: tasks
        singular: task
      scope: Namespaced
      versions:
      - name: v1alpha1
        schema:
          openAPIV3Schema:
            description: Task is the Schema for the tasks API
            properties:
              apiVersion:
                description: 'APIVersion defines the versioned schema of this representation
                  of an object. Servers should convert recognized schemas to the latest
                  internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
                type: string
              kind:
                description: 'Kind is a string value representing the REST resource this
                  object represents. Servers may infer this from the endpoint the client
                  submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                type: string
              metadata:
                type: object
              spec:
                x-kubernetes-preserve-unknown-fields: true
                description: TaskSpec is the desired state for the tasks API.
                properties:
                  id:
                    description: ID is the unique value by which the task is
                      identified.
                    minimum: 1
                    type: string
                required:
                - id
                type: object
              status:
                description: TaskStatus is the observed state of the tasks API.
                type: object
            required:
            - spec
            type: object
        subresources:
          status: {}
        served: true
        storage: false
        additionalPrinterColumns:
        - name: ID
          type: string
          description: The task's unique ID.
          jsonPath: .spec.ID
        - name: Display Name
          type: string
          description: The task's display name.
          jsonPath: .spec.name
        - name: OperationID
          type: string
          description: The ID of the operation with which the task is associated.
          jsonPath: .spec.operationID
        deprecated: true
        deprecationWarning: use v1alpha2 instead, this version causes your data
          center to catch fire when used on Tuesdays
      - name: v1alpha2
        schema:
          openAPIV3Schema:
            description: Task is the Schema for the tasks API
            properties:
              apiVersion:
                description: 'APIVersion defines the versioned schema of this representation
                  of an object. Servers should convert recognized schemas to the latest
                  internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
                type: string
              kind:
                description: 'Kind is a string value representing the REST resource this
                  object represents. Servers may infer this from the endpoint the client
                  submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                type: string
              metadata:
                type: object
              spec:
                description: TaskSpec is the desired state for the tasks API.
                properties:
                  id:
                    description: ID is the unique value by which the task is
                      identified.
                    minimum: 1
                    type: string
                  name:
                    description: Name is a friendly way to refer to the task.
                    type: string
                  operationID:
                    description: OperationID is the external ID used to track the
                      associated operation that spawned this task.
                    type: string
                required:
                - id
                - operationID
                type: object
              status:
                description: TaskStatus is the observed state of the tasks API.
                type: object
                properties:
                  phase:
                    description: Phase describes the current status of the task.
                    type: string
            required:
            - spec
            type: object
        subresources:
          status: {}
        served: true
        storage: true
        additionalPrinterColumns:
        - name: ID
          type: string
          description: The task's unique ID.
          jsonPath: .spec.id
        - name: Display Name
          type: string
          description: The task's display name.
          jsonPath: .spec.name
        - name: OperationID
          type: string
          description: The ID of the operation with which the task is associated.
          jsonPath: .spec.operationID
      conversion:
        strategy: None
    EOF
    ```

1. With `kubectl`, create a new `tasks` resource at schema version `v1alpha2`:

    ```shell
    cat <<EOF | kubectl apply -f -
    apiVersion: akutz.github.com/v1alpha2
    kind: Task
    metadata:
      name: my-task
    spec:
      id: my-required-id
      name: my-optional-name
      operationID: my-required-op-id
    EOF
    ```

1. Print the resource to illustrate everything that should be there _is_ there:

    ```shell
    $ kubectl get task my-task
    NAME      ID               DISPLAY NAME       OPERATIONID
    my-task   my-required-id   my-optional-name   my-required-op-id
    ```

1. With `kubectl`, reconfigure the `tasks` resource, this time at schema version `v1alpha1`:

    ```shell
    cat <<EOF | kubectl apply -f -
    apiVersion: akutz.github.com/v1alpha1
    kind: Task
    metadata:
      name: my-task
    spec:
      id: my-updated-required-id
    EOF
    ```

1. Print the resource once again, revealing the values for fields defined in the `tasks` CRD at version `v1alpha2` have been removed from the resource:

    ```shell
    $ kubectl get task my-task
    NAME      ID                       DISPLAY NAME   OPERATIONID
    my-task   my-updated-required-id 
    ```

1. Just to be sure, explicitly request the `v1alpha2` verison of the resource:

    ```shell
    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
    NAME      ID                       DISPLAY NAME   OPERATIONID
    my-task   my-updated-required-id 
    ```

1. Reapply the resource at `v1alpha2` to restore the missing fields:

    ```shell
    cat <<EOF | kubectl apply -f -
    apiVersion: akutz.github.com/v1alpha2
    kind: Task
    metadata:
      name: my-task
    spec:
      id: my-updated-required-id
      name: my-optional-name
      operationID: my-required-op-id
    EOF
    ```

1. Assert the missing fields have been restored:

    ```shell
    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
    NAME      ID                       DISPLAY NAME       OPERATIONID
    my-task   my-updated-required-id   my-optional-name   my-required-op-id
    ```

1. With `curl`, update the resource at `v1alpha1`:

    ```shell
    curl --cacert ca.crt --cert client.crt --key client.key \
         --silent --show-error \
         -XGET -H 'Accept: application/json' \
         "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task" | \
    jq '.spec.id="my-twice-updated-required-id"' | \
    curl --cacert ca.crt --cert client.crt --key client.key \
         --silent --show-error \
         -XPUT -H 'Content-Type: application/json' -H 'Accept: application/json' -d @- \
         "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
    ```

1. Print the resource, explicitly at `v1alpha2`, to reveal that an `UPDATE` operation with `curl` against the `v1alpha1` version of the resource does __not__ overwrite the values for fields defined at `v1alpha2`:

    ```shell
    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
    NAME      ID                             DISPLAY NAME       OPERATIONID
    my-task   my-twice-updated-required-id   my-optional-name   my-required-op-id
    ```

1. With `curl`, patch the resource at `v1alpha1`:

    ```shell
    curl --cacert ca.crt --cert client.crt --key client.key \
         --silent --show-error \
         -XPATCH -H 'Accept: application/json' -H 'Content-Type: application/json-patch+json' \
         -d '[{"op": "replace", "path": "/spec/id", "value": "my-patched-required-id"}]' \
         "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
    ```

1. Assert the patch did not affect the fields defined at `v1alpha2`:

    ```shell
    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
    NAME      ID                       DISPLAY NAME       OPERATIONID
    my-task   my-patched-required-id   my-optional-name   my-required-op-id
    ```

---

:warning: _The potential for data loss_

With `kubectl` the value of `x-kubernetes-preserve-unknown-fields` makes no difference: reconfiguring a resource at schema version `N-1` can result in the loss of data for fields defined in schema version `N`.

With `curl`, as long as `x-kubernetes-preserve-unknown-fields` is `true` on the `spec` for schema version `N-1`, neither `UPDATE` nor `PATCH` operations with `curl` are  destructive.

However, if `x-kubernetes-preserve-unknown-fields: true` is removed from the `N-1` CRD's `spec` field, then forget about whether an `UPDATE` with `curl` is destructive, even a surgical `PATCH` operation with `curl` against the resource at schema version `N-1` results in the loss of data.

---

1. Remove `x-kubernetes-preserve-unknown-fields: true` from the `v1alpha1` CRD's `spec` field:

    ```shell
    $ kubectl get crd tasks.akutz.github.com -ojson | \
      jq 'del( ( .spec.versions[] ) | select(.name == "v1alpha1").schema.openAPIV3Schema.properties.spec."x-kubernetes-preserve-unknown-fields")' | \
      kubectl apply -f -
    ```

1. With `curl`, patch the resource at `v1alpha1`:

    ```shell
    curl --cacert ca.crt --cert client.crt --key client.key \
         --silent --show-error \
         -XPATCH -H 'Accept: application/json' -H 'Content-Type: application/json-patch+json' \
         -d '[{"op": "replace", "path": "/spec/id", "value": "my-twice-patched-required-id"}]' \
         "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
    ```

1. Assert the patch resulted in data loss for fields defined at `v1alpha2`:

    ```shell
    $  kubectl get tasks.v1alpha2.akutz.github.com/my-task
    NAME      ID                             DISPLAY NAME   OPERATIONID
    my-task   my-twice-patched-required-id
    ```
