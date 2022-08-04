# Patching/updating CRs (pucr) at different versions

This repository provides examples for the observed, unanticipated outcomes when patching and/or updating a custom resource at an older schema version that does not include newer fields for existing types. Values for these fields may be dropped, even when `x-kubernetes-preserve-unknown-fields: true` is enabled, depending on the client.

**What happened:**

Patching and/or updating a custom resource at schema version `N-1` can erase the values of fields defined at version `N` (or subsequent versions) of the API depending on the client used and/or the presence of `x-kubernetes-preserve-unknown-fields: true` in the schema. In fact, this issue goes on to illustrate the following outcomes:

| `x-kubernetes-preserve-unknown-fields` | Client | Operation | Data preserved? |
|:---:|:---:|:---:|:---:|
| `true` | `kubectl` | apply |   |
|   | `curl` | `UPDATE` | ✓ |
|   | `curl` | `PATCH` | ✓ |
|   | client-go _typed_ | `UPDATE` |   |
|   | client-go _typed_ | `PATCH` |  ✓ |
|   | client-go _unstructured_ | `UPDATE` | ✓ |
|   | client-go _unstructured_ | `PATCH` | ✓ |
| _undefined | `kubectl` | apply |   |
|   | `curl` | `UPDATE` |   |
|   | `curl` | `PATCH` |   |
|   | client-go _typed_ | `UPDATE` |   |
|   | client-go _typed_ | `PATCH` |   |
|   | client-go _unstructured_ | `UPDATE` |   |
|   | client-go _unstructured_ | `PATCH` |   |

There is **major** potential for data loss. Simply put, regardless of the client used or the existence of `x-kubernetes-preserve-unknown-fields`, fields defined in later schema versions should not be deleted if a client is operating on a resource using an earlier version of the schema.

**What you expected to happen:**

Patching and/or updating a resource at schema version `N-1` should _not_ erase the values of fields defined at version `N` (or subsequent versions) of the API, _regardless of the client used or the presence of `x-kubernetes-preserve-unknown-fields: true`_.

**How to reproduce it (as minimally and precisely as possible):**

There are two ways to reproduce the issue:

1. **Docker-in-docker** via a container
1. **Natively** on the localhost

Reproducing this issue utilizes the following software:

* **Docker-in-docker**
  * [Docker](https://docs.docker.com/get-docker/) 20.10+
* **Natively**
  * [Docker](https://docs.docker.com/get-docker/) 20.10+
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

        1. Create a new `Dockerfile` with the following contents:

            ```Dockerfile
            FROM golang:1.18
            
            
            ## --------------------------------------
            ## Multi-platform support
            ## --------------------------------------
            
            ARG TARGETOS
            ARG TARGETARCH
            
            
            ## --------------------------------------
            ## Apt and standard packages
            ## --------------------------------------
            
            RUN apt-get update -y && \
                apt-get install -y --no-install-recommends \
                curl jq openssl jq iproute2 iputils-ping tar vim
            
            
            ## --------------------------------------
            ## Install the docker client
            ## --------------------------------------
            
            RUN mkdir -p /etc/apt/keyrings && \
                chmod -R 0755 /etc/apt/keyrings && \
                curl -fsSL "https://download.docker.com/linux/debian/gpg" | \
                  gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg && \
                chmod a+r /etc/apt/keyrings/docker.gpg && \
                echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
                  https://download.docker.com/linux/debian \
                  $(grep VERSION_CODENAME /etc/os-release | \
                  awk -F= '{print $2}') stable" \
                  >/etc/apt/sources.list.d/docker.list && \
                apt-get update -y && \
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-ce-cli
            
            
            ## --------------------------------------
            ## Install yq since there's no apt pkg
            ## --------------------------------------
            
            RUN curl -Lo /usr/bin/yq \
                "https://github.com/mikefarah/yq/releases/download/v4.26.1/yq_linux_${TARGETARCH}" && \
                chmod 0755 /usr/bin/yq
            
            
            ## --------------------------------------
            ## Install kubectl
            ## --------------------------------------
            
            RUN curl -Lo /usr/bin/kubectl \
              "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl" && \
              chmod 0755 /usr/bin/kubectl
            
            
            ## --------------------------------------
            ## Install kind
            ## --------------------------------------
            
            RUN curl -Lo /usr/bin/kind \
              "https://github.com/kubernetes-sigs/kind/releases/download/v0.14.0/kind-linux-${TARGETARCH}" && \
              chmod 0755 /usr/bin/kind
            
            
            ## --------------------------------------
            ## Create a working directory.
            ## --------------------------------------
            
            RUN mkdir /pucr
            WORKDIR /pucr
            
            
            ## --------------------------------------
            ## Enter into a shell
            ## --------------------------------------
            
            ENV DOCKER_IN_DOCKER=1
            ENTRYPOINT ["/bin/bash"]
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

1. Create the following files to define a Golang-based Kubernetes client that uses controller-runtime's typed and unstructured clients, which in turn use client-go:

    * `go.mod`

        ```
        module github.com/akutz/pucr
        
        go 1.18
        
        require (
        	github.com/go-logr/logr v1.2.3
        	k8s.io/apimachinery v0.24.3
        	sigs.k8s.io/controller-runtime v0.12.3
        )
        ```

    * `client.go`

        ```golang
        //go:build client
        // +build client
        
        package main
        
        import (
        	"context"
        	"flag"
        	"os"
        
        	"github.com/go-logr/logr"
        	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
        	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
        	"k8s.io/apimachinery/pkg/runtime"
        	"k8s.io/apimachinery/pkg/runtime/schema"
        	ctrl "sigs.k8s.io/controller-runtime"
        	ctrlclient "sigs.k8s.io/controller-runtime/pkg/client"
        	ctrlconfig "sigs.k8s.io/controller-runtime/pkg/client/config"
        	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
        	"sigs.k8s.io/controller-runtime/pkg/log/zap"
        )
        
        var (
        	log              logr.Logger
        	flagPatch        bool
        	flagUnstructured bool
        	v1alpha1GVK      = schema.GroupVersionKind{
        		Group:   "akutz.github.com",
        		Version: "v1alpha1",
        		Kind:    "Task",
        	}
        )
        
        func main() {
        	// Init flags and the logger.
        	ctrl.SetLogger(zap.New(func(o *zap.Options) { o.Development = true }))
        	log = ctrl.Log.WithName("main")
        	flag.BoolVar(
        		&flagPatch,
        		"patch",
        		false,
        		"indicates to perform a patch operation instead of an update",
        	)
        	flag.BoolVar(
        		&flagUnstructured,
        		"unstructured",
        		false,
        		"indicates to perform the operation using an unstructured object",
        	)
        	flag.Parse()
        
        	// Initialize the scheme.
        	scheme := runtime.NewScheme()
        	metav1.AddToGroupVersion(scheme, v1alpha1GVK.GroupVersion())
        	scheme.AddKnownTypeWithName(v1alpha1GVK, &taskv1a1{})
        
        	// Get the REST config.
        	config, err := ctrlconfig.GetConfigWithContext("kind-pucr")
        	if err != nil {
        		log.Error(err, "failed to get kubeconfig", "context", "kind-pucr")
        		os.Exit(1)
        	}
        
        	// Create a client.
        	client, err := ctrlclient.New(config, ctrlclient.Options{Scheme: scheme})
        	if err != nil {
        		log.Error(err, "failed to create delegated client")
        		os.Exit(1)
        	}
        
        	if flagUnstructured {
        		if flagPatch {
        			log.Info("unstructured patch")
        			untypedPatchV1A1(client)
        		} else {
        			log.Info("unstructured update")
        			untypedUpdateV1A1(client)
        		}
        	} else {
        		if flagPatch {
        			log.Info("typed patch")
        			typedPatchV1A1(client)
        		} else {
        			log.Info("typed update")
        			typedUpdateV1A1(client)
        		}
        	}
        }
        
        func typedUpdateV1A1(client ctrlclient.Client) {
        	obj := &taskv1a1{
        		ObjectMeta: metav1.ObjectMeta{
        			Namespace: "default",
        			Name:      "my-task",
        		},
        	}
        	if _, err := controllerutil.CreateOrUpdate(
        		context.Background(),
        		client,
        		obj,
        		func() error {
        			obj.Spec.ID = "my-updated-required-id"
        			return nil
        		}); err != nil {
        		log.Error(err, "failed to update typed v1alpha1 task")
        		os.Exit(1)
        	}
        }
        
        func typedPatchV1A1(client ctrlclient.Client) {
        	obj := &taskv1a1{
        		ObjectMeta: metav1.ObjectMeta{
        			Namespace: "default",
        			Name:      "my-task",
        		},
        	}
        	if _, err := controllerutil.CreateOrPatch(
        		context.Background(),
        		client,
        		obj,
        		func() error {
        			obj.Spec.ID = "my-patched-required-id"
        			return nil
        		}); err != nil {
        		log.Error(err, "failed to patch typed v1alpha1 task")
        		os.Exit(1)
        	}
        }
        
        func untypedUpdateV1A1(client ctrlclient.Client) {
        	obj := &unstructured.Unstructured{Object: map[string]any{}}
        	obj.SetGroupVersionKind(v1alpha1GVK)
        	obj.SetNamespace("default")
        	obj.SetName("my-task")
        	if _, err := controllerutil.CreateOrUpdate(
        		context.Background(),
        		client,
        		obj,
        		func() error {
        			unstructured.SetNestedField(
        				obj.Object,
        				"my-updated-required-id",
        				"spec", "id",
        			)
        			return nil
        		}); err != nil {
        		log.Error(err, "failed to update unstructured v1alpha1 task")
        		os.Exit(1)
        	}
        }
        
        func untypedPatchV1A1(client ctrlclient.Client) {
        	obj := &unstructured.Unstructured{Object: map[string]any{}}
        	obj.SetGroupVersionKind(v1alpha1GVK)
        	obj.SetNamespace("default")
        	obj.SetName("my-task")
        	if _, err := controllerutil.CreateOrPatch(
        		context.Background(),
        		client,
        		obj,
        		func() error {
        			unstructured.SetNestedField(
        				obj.Object,
        				"my-updated-required-id",
        				"spec", "id",
        			)
        			return nil
        		}); err != nil {
        		log.Error(err, "failed to patch unstructured v1alpha1 task")
        		os.Exit(1)
        	}
        }
        
        type taskv1a1spec struct {
        	ID string `json:"id"`
        }
        
        type taskv1a1 struct {
        	metav1.TypeMeta   `json:",inline"`
        	metav1.ObjectMeta `json:"metadata,omitempty"`
        
        	Spec   taskv1a1spec `json:"spec,omitempty"`
        	Status struct{}     `json:"status,omitempty"`
        }
        
        func (src *taskv1a1) DeepCopyObject() runtime.Object {
        	var dst taskv1a1
        	dst = *src
        	dst.SetGroupVersionKind(src.GroupVersionKind())
        	dst.Spec = src.Spec
        	dst.SetName(src.GetName())
        	dst.SetNamespace(src.GetNamespace())
        	if srcMap := src.GetAnnotations(); srcMap != nil {
        		dstMap := map[string]string{}
        		for k, v := range srcMap {
        			dstMap[k] = v
        		}
        		dst.SetAnnotations(dstMap)
        	}
        	if srcMap := src.GetLabels(); srcMap != nil {
        		dstMap := map[string]string{}
        		for k, v := range srcMap {
        			dstMap[k] = v
        		}
        		dst.SetLabels(dstMap)
        	}
        	return &dst
        }
        ```

1. Update the Go modules:

    ```shell
    go mod tidy
    ```

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

1. Create the following alias to make it easy to delete and reset an example `tasks` resource to a known set of baseline properties:

    ```shell
    cat <<EOF | \
      yq -ojson | \
      jq -c | \
      TASK=$(tee) && \
      alias reset-task='kubectl delete --ignore-not-found task my-task && echo "'"${TASK}"'" | kubectl apply -f -'
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

    Now the command `reset-task` can be used to quickly delete and create a `tasks` resource at `v1alpha2` named `my-task.

1. With `x-kubernetes-preserve-unknown-fields: true` enabled for the `spec` property at version `v1alpha1` of the `tasks` API:

    1. Validate `kubectl`:

        1. Create a new `tasks` resource at `v1alpha2`:
    
            ```shell
            reset-task
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
    
        1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
    
            ```shell
            reset-task
            ```
    
        1. Assert the missing fields have been restored:
    
            ```shell
            $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
            NAME      ID               DISPLAY NAME       OPERATIONID
            my-task   my-required-id   my-optional-name   my-required-op-id
            ```

    1. Validate `curl`:

        1. An `UPDATE` operation:

            1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                ```shell
                reset-task
                ```

            1. With `curl`, update the resource at `v1alpha1`:

                ```shell
                curl --cacert ca.crt --cert client.crt --key client.key \
                     --silent --show-error \
                     -XGET -H 'Accept: application/json' \
                     "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task" | \
                jq '.spec.id="my-updated-required-id"' | \
                curl --cacert ca.crt --cert client.crt --key client.key \
                     --silent --show-error \
                     -XPUT -H 'Content-Type: application/json' -H 'Accept: application/json' -d @- \
                     "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
                ```

            1. Assert the operation did not remove the fields defined at `v1alpha2`:
        
                ```shell
                $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                NAME      ID                       DISPLAY NAME       OPERATIONID
                my-task   my-updated-required-id   my-optional-name   my-required-op-id
                ```

        1. A `PATCH` operation:

            1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                ```shell
                reset-task
                ```

            1. With `curl`, patch the resource at `v1alpha1`:

                ```shell
                curl --cacert ca.crt --cert client.crt --key client.key \
                     --silent --show-error \
                     -XPATCH -H 'Accept: application/json' -H 'Content-Type: application/json-patch+json' \
                     -d '[{"op": "replace", "path": "/spec/id", "value": "my-patched-required-id"}]' \
                     "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
                ```

            1. Assert the operation did not remove the fields defined at `v1alpha2`:
        
                ```shell
                $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                NAME      ID                       DISPLAY NAME       OPERATIONID
                my-task   my-patched-required-id   my-optional-name   my-required-op-id
                ```

    1. Validate Golang / client-go / controller-runtime:

        1. A typed client:

            1. An `UPDATE` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, update the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go
                    ```

                1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-updated-required-id
                    ```

            1. A `PATCH` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, patch the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go -patch
                    ```

                1. Assert the operation did _not_ result in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-patched-required-id   my-optional-name   my-required-op-id
                    ```

        1. An unstructured client:

            1. An `UPDATE` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, update the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go -unstructured
                    ```

                1. Assert the operation did _not_ result in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-updated-required-id   my-optional-name   my-required-op-id
                    ```

            1. A `PATCH` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, patch the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go -unstructured -patch
                    ```

                1. Assert the operation did _not_ result in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-patched-required-id   my-optional-name   my-required-op-id
                    ```

1. Next, disable the preservation of unknown fields for the `spec` property in the `v1alpha1` CRD:

    ```shell
    $ kubectl get crd tasks.akutz.github.com -ojson | \
      jq 'del((.spec.versions[] | select(.name == "v1alpha1")).schema.openAPIV3Schema.properties.spec."x-kubernetes-preserve-unknown-fields")' | \
      kubectl apply -f -
    ```

1. With `x-kubernetes-preserve-unknown-fields` no longer enabled, validate the following:

    1. Validate `kubectl`:

        1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
            ```shell
            reset-task
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
        
        1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

            ```shell
            $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
            NAME      ID                       DISPLAY NAME       OPERATIONID
            my-task   my-updated-required-id
            ```

    1. Validate `curl`:

        1. An `UPDATE` operation:

            1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                ```shell
                reset-task
                ```

            1. With `curl`, update the resource at `v1alpha1`:

                ```shell
                curl --cacert ca.crt --cert client.crt --key client.key \
                     --silent --show-error \
                     -XGET -H 'Accept: application/json' \
                     "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task" | \
                jq '.spec.id="my-updated-required-id"' | \
                curl --cacert ca.crt --cert client.crt --key client.key \
                     --silent --show-error \
                     -XPUT -H 'Content-Type: application/json' -H 'Accept: application/json' -d @- \
                     "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
                ```

            1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                ```shell
                $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                NAME      ID                       DISPLAY NAME       OPERATIONID
                my-task   my-updated-required-id
                ```

        1. A `PATCH` operation:

            1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                ```shell
                reset-task
                ```

            1. With `curl`, patch the resource at `v1alpha1`:

                ```shell
                curl --cacert ca.crt --cert client.crt --key client.key \
                     --silent --show-error \
                     -XPATCH -H 'Accept: application/json' -H 'Content-Type: application/json-patch+json' \
                     -d '[{"op": "replace", "path": "/spec/id", "value": "my-patched-required-id"}]' \
                     "$(cat url.txt)/apis/akutz.github.com/v1alpha1/namespaces/default/tasks/my-task"
                ```

            1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                ```shell
                $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                NAME      ID                       DISPLAY NAME       OPERATIONID
                my-task   my-patched-required-id
                ```

    1. Validate Golang / client-go / controller-runtime:

        1. A typed client:

            1. An `UPDATE` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, update the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go
                    ```

                1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-updated-required-id
                    ```

            1. A `PATCH` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, patch the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go -patch
                    ```

                1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-patched-required-id
                    ```

        1. An unstructured client:

            1. An `UPDATE` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, update the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go -unstructured
                    ```

                1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-updated-required-id
                    ```

            1. A `PATCH` operation:

                1. Delete the resource and recreate it at `v1alpha2` to reset to baseline:
            
                    ```shell
                    reset-task
                    ```

                1. With `client.go`, patch the resource at `v1alpha1`:
                
                    ```shell
                    go run -tags client client.go -unstructured -patch
                    ```

                1. Assert the operation resulted in data loss for fields defined at `v1alpha2`:

                    ```shell
                    $ kubectl get tasks.v1alpha2.akutz.github.com/my-task
                    NAME      ID                       DISPLAY NAME       OPERATIONID
                    my-task   my-patched-required-id
                    ```

**Anything else we need to know?**:

_NA_
