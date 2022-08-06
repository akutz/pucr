//go:build server
// +build server

package main

import (
	"crypto/tls"
	gojson "encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"

	"github.com/munnerz/goautoneg"

	apiextv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer/json"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/klog"
)

func convertExampleCRD(fromObj *unstructured.Unstructured, toVersion string) (*unstructured.Unstructured, metav1.Status) {
	klog.V(2).Info("converting crd")

	toObj := fromObj.DeepCopy()
	fromVersion := fromObj.GetAPIVersion()

	if toVersion == fromVersion {
		return nil, statusErrorWithMessage("conversion from a version to itself should not call the webhook: %s", toVersion)
	}

	switch fromVersion {
	case "akutz.github.com/v1alpha1":
		switch toVersion {
		case "akutz.github.com/v1alpha2":
			if v1a2JSON, ok := fromObj.GetAnnotations()["obj.v1alpha2"]; ok {
				v1a2Obj := unstructured.Unstructured{Object: map[string]interface{}{}}
				if err := gojson.Unmarshal([]byte(v1a2JSON), &v1a2Obj.Object); err != nil {
					return nil, statusErrorWithMessage("unexpected conversion error", err)
				}
				name, _, err := unstructured.NestedString(v1a2Obj.Object, "name")
				if err != nil {
					return nil, statusErrorWithMessage("unexpected conversion error", err)
				}
				operationID, _, err := unstructured.NestedString(v1a2Obj.Object, "operationID")
				if err != nil {
					return nil, statusErrorWithMessage("unexpected conversion error", err)
				}
				unstructured.SetNestedField(toObj.Object, name, "spec", "name")
				unstructured.SetNestedField(toObj.Object, operationID, "spec", "operationID")

				toAnnotations := toObj.GetAnnotations()
				delete(toAnnotations, "obj.v1alpha2")
				toObj.SetAnnotations(toAnnotations)
			}
		default:
			return nil, statusErrorWithMessage("unexpected conversion version %q", toVersion)
		}
	case "akutz.github.com/v1alpha2":
		switch toVersion {
		case "akutz.github.com/v1alpha1":
			fromSpec, ok, err := unstructured.NestedFieldCopy(fromObj.Object, "spec")
			if err != nil {
				return nil, statusErrorWithMessage("unexpected conversion error", err)
			}
			if ok {
				fromJSON, err := gojson.Marshal(fromSpec)
				if err != nil {
					return nil, statusErrorWithMessage("unexpected conversion error", err)
				}
				toAnnotations := toObj.GetAnnotations()
				if toAnnotations == nil {
					toAnnotations = map[string]string{}
				}
				toAnnotations["obj.v1alpha2"] = string(fromJSON)
				toObj.SetAnnotations(toAnnotations)
			} else {
				fmt.Println("no spec")
			}
		default:
			return nil, statusErrorWithMessage("unexpected conversion version %q", toVersion)
		}
	default:
		return nil, statusErrorWithMessage("unexpected conversion version %q", fromVersion)
	}
	return toObj, statusSucceed()
}

// convertFunc is the user defined function for any conversion. The code in this file is a
// template that can be use for any CR conversion given this function.
type convertFunc func(fromObj *unstructured.Unstructured, version string) (*unstructured.Unstructured, metav1.Status)

// conversionResponseFailureWithMessagef is a helper function to create an AdmissionResponse
// with a formatted embedded error message.
func conversionResponseFailureWithMessagef(msg string, params ...interface{}) *apiextv1.ConversionResponse {
	return &apiextv1.ConversionResponse{
		Result: metav1.Status{
			Message: fmt.Sprintf(msg, params...),
			Status:  metav1.StatusFailure,
		},
	}

}

func statusErrorWithMessage(msg string, params ...interface{}) metav1.Status {
	return metav1.Status{
		Message: fmt.Sprintf(msg, params...),
		Status:  metav1.StatusFailure,
	}
}

func statusSucceed() metav1.Status {
	return metav1.Status{
		Status: metav1.StatusSuccess,
	}
}

// doConversion converts the requested object given the conversion function and returns a conversion response.
// failures will be reported as Reason in the conversion response.
func doConversion(convertRequest *apiextv1.ConversionRequest, convert convertFunc) *apiextv1.ConversionResponse {
	var toObjs []runtime.RawExtension
	for _, obj := range convertRequest.Objects {
		cr := unstructured.Unstructured{}
		if err := cr.UnmarshalJSON(obj.Raw); err != nil {
			klog.Error(err)
			return conversionResponseFailureWithMessagef("failed to unmarshall object (%v) with error: %v", string(obj.Raw), err)
		}
		convertedCR, status := convert(&cr, convertRequest.DesiredAPIVersion)
		if status.Status != metav1.StatusSuccess {
			klog.Error(status.String())
			return &apiextv1.ConversionResponse{
				Result: status,
			}
		}
		convertedCR.SetAPIVersion(convertRequest.DesiredAPIVersion)
		toObjs = append(toObjs, runtime.RawExtension{Object: convertedCR})
	}
	return &apiextv1.ConversionResponse{
		ConvertedObjects: toObjs,
		Result:           statusSucceed(),
	}
}

func serve(w http.ResponseWriter, r *http.Request, convert convertFunc) {
	var body []byte
	if r.Body != nil {
		if data, err := ioutil.ReadAll(r.Body); err == nil {
			body = data
		}
	}

	contentType := r.Header.Get("Content-Type")
	serializer := getInputSerializer(contentType)
	if serializer == nil {
		msg := fmt.Sprintf("invalid Content-Type header `%s`", contentType)
		klog.Errorf(msg)
		http.Error(w, msg, http.StatusBadRequest)
		return
	}

	klog.V(2).Infof("handling request: %v", body)
	convertReview := apiextv1.ConversionReview{}
	if _, _, err := serializer.Decode(body, nil, &convertReview); err != nil {
		klog.Error(err)
		convertReview.Response = conversionResponseFailureWithMessagef("failed to deserialize body (%v) with error %v", string(body), err)
	} else {
		convertReview.Response = doConversion(convertReview.Request, convert)
		convertReview.Response.UID = convertReview.Request.UID
	}
	klog.V(2).Info(fmt.Sprintf("sending response: %v", convertReview.Response))

	// reset the request, it is not needed in a response.
	convertReview.Request = &apiextv1.ConversionRequest{}

	accept := r.Header.Get("Accept")
	outSerializer := getOutputSerializer(accept)
	if outSerializer == nil {
		msg := fmt.Sprintf("invalid accept header `%s`", accept)
		klog.Errorf(msg)
		http.Error(w, msg, http.StatusBadRequest)
		return
	}
	err := outSerializer.Encode(&convertReview, w)
	if err != nil {
		klog.Error(err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}

// ServeExampleConvert servers endpoint for the example converter defined as convertExampleCRD function.
func ServeExampleConvert(w http.ResponseWriter, r *http.Request) {
	serve(w, r, convertExampleCRD)
}

type mediaType struct {
	Type, SubType string
}

var scheme = runtime.NewScheme()
var serializers = map[mediaType]runtime.Serializer{
	{"application", "json"}: json.NewSerializer(json.DefaultMetaFactory, scheme, scheme, false),
	{"application", "yaml"}: json.NewYAMLSerializer(json.DefaultMetaFactory, scheme, scheme),
}

func getInputSerializer(contentType string) runtime.Serializer {
	parts := strings.SplitN(contentType, "/", 2)
	if len(parts) != 2 {
		return nil
	}
	return serializers[mediaType{parts[0], parts[1]}]
}

func getOutputSerializer(accept string) runtime.Serializer {
	if len(accept) == 0 {
		return serializers[mediaType{"application", "json"}]
	}

	clauses := goautoneg.ParseAccept(accept)
	for _, clause := range clauses {
		for k, v := range serializers {
			switch {
			case clause.Type == k.Type && clause.SubType == k.SubType,
				clause.Type == k.Type && clause.SubType == "*",
				clause.Type == "*" && clause.SubType == "*":
				return v
			}
		}
	}

	return nil
}

// Get a clientset with in-cluster config.
func getClient() *kubernetes.Clientset {
	config, err := rest.InClusterConfig()
	if err != nil {
		klog.Fatal(err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		klog.Fatal(err)
	}
	return clientset
}

func configTLS(config Config, clientset *kubernetes.Clientset) *tls.Config {
	sCert, err := tls.LoadX509KeyPair(config.CertFile, config.KeyFile)
	if err != nil {
		klog.Fatal(err)
	}
	return &tls.Config{
		Certificates: []tls.Certificate{sCert},
		// TODO: uses mutual tls after we agree on what cert the apiserver should use.
		// ClientAuth:   tls.RequireAndVerifyClientCert,
	}
}

type Config struct {
	CertFile string
	KeyFile  string
}

func (c *Config) addFlags() {
	flag.StringVar(&c.CertFile, "tls-cert-file", c.CertFile, "/webhook/server.crt"+
		"File containing the default x509 Certificate for HTTPS. (CA cert, if any, concatenated "+
		"after server cert).")
	flag.StringVar(&c.KeyFile, "tls-private-key-file", c.KeyFile, "/webhook/server.key"+
		"File containing the default x509 private key matching --tls-cert-file.")
}

func main() {
	var config Config
	config.addFlags()
	flag.Parse()

	http.HandleFunc("/crdconvert", ServeExampleConvert)
	clientset := getClient()
	server := &http.Server{
		Addr:      ":9443",
		TLSConfig: configTLS(config, clientset),
	}
	server.ListenAndServeTLS("", "")
}
