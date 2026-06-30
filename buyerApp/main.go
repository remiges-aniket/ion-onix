package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

var (
	bapCallerURL = getEnv("BAP_CALLER_URL", "http://onix-bap:8081/bap/caller")
	networkID    = getEnv("NETWORK_ID", "ion.id/ION-DC-Registry")
	bapID        = getEnv("BAP_ID", "dc-bap.ion.id")
	bapURI       = getEnv("BAP_URI", "http://onix-bap:8081/bap/receiver")
	bppID        = getEnv("BPP_ID", "dc-bpp.ion.id")
	bppURI       = getEnv("BPP_URI", "http://onix-bpp:8082/bpp/receiver")
	serverPort   = getEnv("PORT", "3001")
)

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

type BecknMsg struct {
	Context map[string]interface{} `json:"context"`
	Message map[string]interface{} `json:"message"`
}

type SearchRequest struct {
	Query string `json:"query"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/bap-webhook/", handleWebhook)
	mux.HandleFunc("/api/search", handleSearch)
	mux.HandleFunc("/api/select", handleSelect)
	mux.HandleFunc("/api/init", handleInit)
	mux.HandleFunc("/api/confirm", handleConfirm)
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"status":"ok"}`)
	})

	addr := ":" + serverPort
	log.Printf("buyer-app listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

// handleWebhook receives on_* callbacks from the BAP adapter
func handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "read body failed", http.StatusBadRequest)
		return
	}

	var req BecknMsg
	if err := json.Unmarshal(body, &req); err != nil {
		log.Printf("[webhook] decode error: %v\nbody: %s", err, string(body))
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	action, _ := req.Context["action"].(string)
	txID, _ := req.Context["transactionId"].(string)
	log.Printf("[webhook] RECEIVED action=%s transactionId=%s", action, txID)

	// Pretty-print the message for debugging
	if msgBytes, err := json.MarshalIndent(req.Message, "", "  "); err == nil {
		log.Printf("[webhook] message:\n%s", string(msgBytes))
	}

	// Return ACK
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"message":{"ack":{"status":"ACK"}}}`)
}

// handleSearch triggers a discover request to the BAP caller
func handleSearch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, _ := io.ReadAll(r.Body)

	var req SearchRequest
	if err := json.Unmarshal(body, &req); err != nil || req.Query == "" {
		req.Query = "thermos flask"
	}

	discoverBody := map[string]interface{}{
		"context": map[string]interface{}{
			"version":       "2.0.0",
			"action":        "discover",
			"timestamp":     time.Now().UTC().Format(time.RFC3339),
			"messageId":     newUUID(),
			"transactionId": newUUID(),
			"bapId":         bapID,
			"bapUri":        bapURI,
			"ttl":           "PT30S",
			"networkId":     networkID,
		},
		"message": map[string]interface{}{
			"intent": map[string]interface{}{
				"textSearch": req.Query,
			},
		},
	}

	data, err := json.Marshal(discoverBody)
	if err != nil {
		http.Error(w, "marshal failed", http.StatusInternalServerError)
		return
	}

	url := fmt.Sprintf("%s/discover", bapCallerURL)
	log.Printf("[search] sending discover to %s for query: %s", url, req.Query)

	resp, err := http.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		log.Printf("[search] error: %v", err)
		http.Error(w, fmt.Sprintf("discover failed: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	log.Printf("[search] discover response %d: %s", resp.StatusCode, string(respBody))

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	w.Write(respBody)
}

// becknContext builds a base Beckn v2 context with both BAP and BPP fields
func becknContext(action, txID string) map[string]interface{} {
	if txID == "" {
		txID = newUUID()
	}
	return map[string]interface{}{
		"version":       "2.0.0",
		"action":        action,
		"timestamp":     time.Now().UTC().Format(time.RFC3339),
		"messageId":     newUUID(),
		"transactionId": txID,
		"bapId":         bapID,
		"bapUri":        bapURI,
		"bppId":         bppID,
		"bppUri":        bppURI,
		"ttl":           "PT30S",
		"networkId":     networkID,
	}
}

func postAction(action string, body map[string]interface{}, w http.ResponseWriter) {
	data, err := json.Marshal(body)
	if err != nil {
		http.Error(w, "marshal failed", http.StatusInternalServerError)
		return
	}
	url := fmt.Sprintf("%s/%s", bapCallerURL, action)
	log.Printf("[%s] sending to %s", action, url)
	resp, err := http.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		log.Printf("[%s] error: %v", action, err)
		http.Error(w, fmt.Sprintf("%s failed: %v", action, err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	log.Printf("[%s] response %d: %s", action, resp.StatusCode, string(respBody))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	w.Write(respBody)
}

func handleSelect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, _ := io.ReadAll(r.Body)
	var req map[string]interface{}
	txID := ""
	if json.Unmarshal(body, &req) == nil {
		if v, ok := req["transactionId"].(string); ok {
			txID = v
		}
	}
	postAction("select", map[string]interface{}{
		"context": becknContext("select", txID),
		"message": map[string]interface{}{
			"contract": map[string]interface{}{
				"status": map[string]interface{}{"code": "DRAFT"},
				"participants": []interface{}{
					map[string]interface{}{"id": "provider-ion-seller-001", "descriptor": map[string]interface{}{"name": "ION Seller Store"}},
					map[string]interface{}{"id": "buyer-test-001", "descriptor": map[string]interface{}{"name": "Test Buyer"}},
				},
				"commitments": []interface{}{
					map[string]interface{}{
						"id":        "commitment-001",
						"status":    map[string]interface{}{"descriptor": map[string]interface{}{"code": "DRAFT"}},
						"resources": []interface{}{map[string]interface{}{"id": "tushar-thermos-flask-500ml", "quantity": 1}},
						"offer":     map[string]interface{}{"id": "offer-thermos-flask"},
					},
				},
				"performance": []interface{}{
					map[string]interface{}{"id": "perf-001", "status": map[string]interface{}{"code": "PENDING"}, "commitmentIds": []interface{}{"commitment-001"}},
				},
			},
		},
	}, w)
}

func handleInit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, _ := io.ReadAll(r.Body)
	var req map[string]interface{}
	txID := ""
	if json.Unmarshal(body, &req) == nil {
		if v, ok := req["transactionId"].(string); ok {
			txID = v
		}
	}
	postAction("init", map[string]interface{}{
		"context": becknContext("init", txID),
		"message": map[string]interface{}{
			"contract": map[string]interface{}{
				"status": map[string]interface{}{"code": "DRAFT"},
				"participants": []interface{}{
					map[string]interface{}{"id": "provider-ion-seller-001", "descriptor": map[string]interface{}{"name": "ION Seller Store"}},
					map[string]interface{}{
						"id":         "buyer-test-001",
						"descriptor": map[string]interface{}{"name": "Test Buyer"},
						"contactDetails": map[string]interface{}{
							"phone": "+6281234567890",
							"email": "buyer@test.com",
						},
						"address": map[string]interface{}{
							"street": "Jl. Sudirman No. 1",
							"city":   "Jakarta",
							"zip":    "10220",
						},
					},
				},
				"commitments": []interface{}{
					map[string]interface{}{
						"id":        "commitment-001",
						"status":    map[string]interface{}{"descriptor": map[string]interface{}{"code": "DRAFT"}},
						"resources": []interface{}{map[string]interface{}{"id": "tushar-thermos-flask-500ml", "quantity": 1}},
						"offer":     map[string]interface{}{"id": "offer-thermos-flask"},
					},
				},
				"performance": []interface{}{
					map[string]interface{}{"id": "perf-001", "status": map[string]interface{}{"code": "PENDING"}, "commitmentIds": []interface{}{"commitment-001"}},
				},
			},
		},
	}, w)
}

func handleConfirm(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, _ := io.ReadAll(r.Body)
	var req map[string]interface{}
	txID := ""
	if json.Unmarshal(body, &req) == nil {
		if v, ok := req["transactionId"].(string); ok {
			txID = v
		}
	}
	postAction("confirm", map[string]interface{}{
		"context": becknContext("confirm", txID),
		"message": map[string]interface{}{
			"contract": map[string]interface{}{
				"status": map[string]interface{}{"code": "DRAFT"},
				"participants": []interface{}{
					map[string]interface{}{"id": "provider-ion-seller-001", "descriptor": map[string]interface{}{"name": "ION Seller Store"}},
					map[string]interface{}{"id": "buyer-test-001", "descriptor": map[string]interface{}{"name": "Test Buyer"}},
				},
				"commitments": []interface{}{
					map[string]interface{}{
						"id":        "commitment-001",
						"status":    map[string]interface{}{"descriptor": map[string]interface{}{"code": "DRAFT"}},
						"resources": []interface{}{map[string]interface{}{"id": "tushar-thermos-flask-500ml", "quantity": 1}},
						"offer":     map[string]interface{}{"id": "offer-thermos-flask"},
					},
				},
				"performance": []interface{}{
					map[string]interface{}{"id": "perf-001", "status": map[string]interface{}{"code": "PENDING"}, "commitmentIds": []interface{}{"commitment-001"}},
				},
			},
		},
	}, w)
}

func newUUID() string {
	return fmt.Sprintf("%x-%x-%x-%x-%x",
		time.Now().UnixNano()&0xffffffff,
		time.Now().UnixNano()>>32&0xffff,
		(time.Now().UnixNano()>>48&0x0fff)|0x4000,
		(time.Now().UnixNano()>>56&0x3fff)|0x8000,
		time.Now().UnixNano()&0xffffffffffff,
	)
}
