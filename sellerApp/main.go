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
	bppCallerURL = getEnv("BPP_CALLER_URL", "http://onix-bpp:8082/bpp/caller")
	networkID    = getEnv("NETWORK_ID", "ion.id/ION-DC-Registry")
	bppID        = getEnv("BPP_ID", "dc-bpp.ion.id")
	bppURI       = getEnv("BPP_URI", "http://onix-bpp:8082/bpp/receiver")
	serverPort   = getEnv("PORT", "3002")
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

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/webhook/", handleWebhook)
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"status":"ok"}`)
	})

	// Publish catalog once adapter is ready
	go func() {
		time.Sleep(12 * time.Second)
		if err := publishCatalog(); err != nil {
			log.Printf("catalog publish failed: %v", err)
		} else {
			log.Println("catalog published successfully")
		}
	}()

	addr := ":" + serverPort
	log.Printf("seller-app listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

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
		log.Printf("webhook json decode error: %v\nbody: %s", err, string(body))
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	action, _ := req.Context["action"].(string)
	txID, _ := req.Context["transactionId"].(string)
	log.Printf("[webhook] action=%s transactionId=%s", action, txID)

	// Immediate ACK
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, `{"message":{"ack":{"status":"ACK"}}}`)

	// Async response
	go func() {
		if err := handleAction(req, action); err != nil {
			log.Printf("[async] handleAction(%s) error: %v", action, err)
		}
	}()
}

func handleAction(req BecknMsg, action string) error {
	responseAction, msg := buildResponse(req, action)
	if responseAction == "" {
		log.Printf("[handleAction] no handler for action: %s", action)
		return nil
	}

	ctx := cloneCtx(req.Context)
	ctx["action"] = responseAction
	ctx["messageId"] = newUUID()
	ctx["timestamp"] = time.Now().UTC().Format(time.RFC3339Nano)
	// Ensure bppId and bppUri are set
	if _, ok := ctx["bppId"]; !ok {
		ctx["bppId"] = bppID
	}
	if _, ok := ctx["bppUri"]; !ok {
		ctx["bppUri"] = bppURI
	}

	resp := BecknMsg{Context: ctx, Message: msg}
	return postToCaller(responseAction, resp)
}

func buildResponse(req BecknMsg, action string) (string, map[string]interface{}) {
	contract := deepGet(req.Message, "contract")

	switch action {
	case "discover":
		return "on_discover", buildOnDiscover()
	case "select":
		return "on_select", buildOnSelect(contract)
	case "init":
		return "on_init", buildOnInit(contract)
	case "confirm":
		return "on_confirm", buildOnConfirm(contract)
	case "status":
		return "on_status", buildOnStatus(contract)
	case "cancel":
		return "on_cancel", buildOnCancel(contract)
	case "support":
		return "on_support", buildOnSupport(req.Message)
	default:
		return "", nil
	}
}

// buildOnDiscover returns our catalog in on_discover format
func buildOnDiscover() map[string]interface{} {
	now := time.Now().UTC().Format(time.RFC3339)
	end := time.Now().UTC().AddDate(1, 0, 0).Format(time.RFC3339)
	return map[string]interface{}{
		"catalogs": []interface{}{buildCatalogEntry(now, end)},
	}
}

// buildCatalogEntry is the single source of truth for all product data.
// To add/rename a product: update resources[] and offers[] below.
// Rule: every offer.resourceIds entry must match a resource.id in the same list.
func buildCatalogEntry(startDate, endDate string) map[string]interface{} {
	providerRef := map[string]interface{}{
		"id":         "provider-ion-seller-001",
		"descriptor": map[string]interface{}{"name": "ION Seller Store Jakarta"},
	}
	validity := map[string]interface{}{"startDate": startDate, "endDate": endDate}
	return map[string]interface{}{
		"id":     "catalog-ion-seller-001",
		"bppId":  bppID,
		"bppUri": bppURI,
		"descriptor": map[string]interface{}{
			"name":      "ION Seller Store",
			"shortDesc": "General goods and electronics catalog",
		},
		"provider": providerRef,
		"validity": validity,
		// ── Resources: one entry per physical product ────────────────────────
		// Change "name"/"shortDesc" freely. Keep "id" stable — offers reference it.
		"resources": []interface{}{
			map[string]interface{}{
				"id": "tushar-thermos-flask-500ml",
				"descriptor": map[string]interface{}{
					"name":      "Tushar Thermos Flask 500ml",
					"shortDesc": "Double-wall stainless steel vacuum flask, keeps drinks hot/cold 12 hours",
					"mediaFile": []interface{}{
						map[string]interface{}{
							"label":    "Product Image",
							"mimeType": "image/jpeg",
							"uri":      "https://tourism-bpp-infra2.becknprotocol.io/attachments/view/253.jpg",
						},
					},
				},
				"resourceAttributes": map[string]interface{}{
					"@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailResource/v2.1/context.jsonld",
					"@type":    "RetailResource",
					"identity": map[string]interface{}{"brand": "ThermoMax", "originCountry": "ID"},
					"physical": map[string]interface{}{
						"weight":     map[string]interface{}{"unitCode": "G", "unitQuantity": 320},
						"volume":     map[string]interface{}{"unitCode": "ML", "unitQuantity": 500},
						"appearance": map[string]interface{}{"color": "Silver", "material": "Stainless Steel 304", "finish": "Matte"},
					},
				},
			},
			map[string]interface{}{
				"id": "item-backpack-20l",
				"descriptor": map[string]interface{}{
					"name":      "Hiking Backpack 20L",
					"shortDesc": "Lightweight 20L hiking backpack with rain cover",
				},
				"resourceAttributes": map[string]interface{}{
					"@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailResource/v2.1/context.jsonld",
					"@type":    "RetailResource",
					"identity": map[string]interface{}{"brand": "TrailGear", "originCountry": "ID"},
					"physical": map[string]interface{}{
						"weight":     map[string]interface{}{"unitCode": "G", "unitQuantity": 450},
						"volume":     map[string]interface{}{"unitCode": "L", "unitQuantity": 20},
						"appearance": map[string]interface{}{"color": "Black/Green", "material": "Polyester 300D"},
					},
				},
			},
		},
		// ── Offers: purchasable listings that reference resource IDs ─────────
		// offer.resourceIds must exactly match resource.id values above.
		"offers": []interface{}{
			map[string]interface{}{
				"id":          "offer-thermos-flask",
				"descriptor":  map[string]interface{}{"name": "Tushar Thermos Flask 500ml"},
				"resourceIds": []interface{}{"tushar-thermos-flask-500ml"},
				"provider":    providerRef,
				"validity":    validity,
				"offerAttributes": map[string]interface{}{
					"@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailOffer/v2.1/context.jsonld",
					"@type":    "RetailOffer",
					"policies": map[string]interface{}{
						"returns":      map[string]interface{}{"allowed": true, "window": "P7D", "method": "SELLER_PICKUP"},
						"cancellation": map[string]interface{}{"allowed": true, "window": "PT2H", "cutoffEvent": "BEFORE_PACKING"},
					},
					"paymentConstraints": map[string]interface{}{"codAvailable": true},
					"serviceability": map[string]interface{}{
						"distanceConstraint": map[string]interface{}{"maxDistance": 30, "unit": "KM"},
						"timing": []interface{}{
							map[string]interface{}{
								"daysOfWeek": []interface{}{"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"},
								"timeRange":  map[string]interface{}{"start": "09:00", "end": "21:00"},
							},
						},
					},
				},
			},
			map[string]interface{}{
				"id":          "offer-backpack-20l",
				"descriptor":  map[string]interface{}{"name": "Hiking Backpack 20L"},
				"resourceIds": []interface{}{"item-backpack-20l"},
				"provider":    providerRef,
				"validity":    validity,
				"offerAttributes": map[string]interface{}{
					"@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailOffer/v2.1/context.jsonld",
					"@type":    "RetailOffer",
					"policies": map[string]interface{}{
						"returns":      map[string]interface{}{"allowed": true, "window": "P10D", "method": "SELLER_PICKUP"},
						"cancellation": map[string]interface{}{"allowed": true, "window": "PT4H", "cutoffEvent": "BEFORE_PACKING"},
					},
					"paymentConstraints": map[string]interface{}{"codAvailable": true},
					"serviceability": map[string]interface{}{
						"distanceConstraint": map[string]interface{}{"maxDistance": 30, "unit": "KM"},
						"timing": []interface{}{
							map[string]interface{}{
								"daysOfWeek": []interface{}{"MON", "TUE", "WED", "THU", "FRI", "SAT"},
								"timeRange":  map[string]interface{}{"start": "09:00", "end": "21:00"},
							},
						},
					},
				},
			},
		},
	}
}

// buildOnSelect adds pricing consideration to the contract
func buildOnSelect(contract interface{}) map[string]interface{} {
	c := cloneMap(toMap(contract))
	c["consideration"] = []interface{}{
		map[string]interface{}{
			"id":     "consideration-001",
			"status": map[string]interface{}{"code": "QUOTED"},
			"considerationAttributes": map[string]interface{}{
				"@context":    "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailConsideration/v2.1/context.jsonld",
				"@type":       "RetailConsideration",
				"currency":    "IDR",
				"totalAmount": 150000.0,
				"breakup": []interface{}{
					map[string]interface{}{"title": "Item price", "amount": 130000.0, "type": "BASE_PRICE"},
					map[string]interface{}{"title": "PPN 15%", "amount": 20000.0, "type": "TAX"},
				},
				"paymentMethods": []interface{}{"PREPAID", "COD", "CREDIT_CARD"},
			},
		},
	}
	// Enrich commitment prices
	enrichCommitmentPrices(c)
	return map[string]interface{}{"contract": c}
}

// buildOnInit adds a contract ID and settlement details
func buildOnInit(contract interface{}) map[string]interface{} {
	c := cloneMap(toMap(contract))
	if _, hasID := c["id"]; !hasID {
		c["id"] = newUUID()
	}
	c["consideration"] = []interface{}{
		map[string]interface{}{
			"id":     "consideration-001",
			"status": map[string]interface{}{"code": "QUOTED"},
			"considerationAttributes": map[string]interface{}{
				"@context":    "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailConsideration/v2.1/context.jsonld",
				"@type":       "RetailConsideration",
				"currency":    "IDR",
				"totalAmount": 150000.0,
				"breakup": []interface{}{
					map[string]interface{}{"title": "Item price", "amount": 130000.0, "type": "BASE_PRICE"},
					map[string]interface{}{"title": "PPN 15%", "amount": 20000.0, "type": "TAX"},
				},
				"paymentMethods": []interface{}{"PREPAID", "COD"},
				"settlements": []interface{}{
					map[string]interface{}{
						"id":     "settlement-001",
						"status": map[string]interface{}{"code": "PENDING"},
						"settlementAttributes": map[string]interface{}{
							"@context":      "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailSettlement/v2.1/context.jsonld",
							"@type":         "RetailSettlement",
							"method":        "BANK_TRANSFER",
							"settledAt":     time.Now().UTC().Add(30 * time.Minute).Format(time.RFC3339),
							"settledAmount": 150000.0,
							"currency":      "IDR",
						},
					},
				},
			},
		},
	}
	enrichCommitmentPrices(c)
	setContractAttributes(c)
	return map[string]interface{}{"contract": c}
}

// buildOnConfirm marks the contract as ACTIVE
func buildOnConfirm(contract interface{}) map[string]interface{} {
	c := cloneMap(toMap(contract))
	if _, hasID := c["id"]; !hasID {
		c["id"] = newUUID()
	}
	c["status"] = map[string]interface{}{"code": "ACTIVE"}

	// Update commitment statuses
	if commitments, ok := c["commitments"].([]interface{}); ok {
		for _, cm := range commitments {
			if cmMap, ok := cm.(map[string]interface{}); ok {
				cmMap["status"] = map[string]interface{}{"descriptor": map[string]interface{}{"code": "ACTIVE"}}
			}
		}
	}
	// Update performance statuses
	if perfs, ok := c["performance"].([]interface{}); ok {
		for _, p := range perfs {
			if pm, ok := p.(map[string]interface{}); ok {
				pm["status"] = map[string]interface{}{"code": "ORDER_PLACED"}
			}
		}
	}
	// Update consideration status
	if cons, ok := c["consideration"].([]interface{}); ok {
		for _, con := range cons {
			if cm, ok := con.(map[string]interface{}); ok {
				cm["status"] = map[string]interface{}{"code": "AGREED"}
			}
		}
	} else {
		c["consideration"] = []interface{}{
			map[string]interface{}{
				"id":     "consideration-001",
				"status": map[string]interface{}{"code": "AGREED"},
				"considerationAttributes": map[string]interface{}{
					"@context":    "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailConsideration/v2.1/context.jsonld",
					"@type":       "RetailConsideration",
					"currency":    "IDR",
					"totalAmount": 150000.0,
					"breakup": []interface{}{
						map[string]interface{}{"title": "Item price", "amount": 130000.0, "type": "BASE_PRICE"},
						map[string]interface{}{"title": "PPN 15%", "amount": 20000.0, "type": "TAX"},
					},
					"paymentMethods": []interface{}{"PREPAID", "COD"},
				},
			},
		}
	}
	enrichCommitmentPrices(c)
	setContractAttributes(c)
	return map[string]interface{}{"contract": c}
}

// buildOnStatus returns the contract with current fulfillment status
func buildOnStatus(contract interface{}) map[string]interface{} {
	c := cloneMap(toMap(contract))
	if c["status"] == nil {
		c["status"] = map[string]interface{}{"code": "ACTIVE"}
	}
	if perfs, ok := c["performance"].([]interface{}); ok && len(perfs) > 0 {
		if pm, ok := perfs[0].(map[string]interface{}); ok {
			if pm["status"] == nil {
				pm["status"] = map[string]interface{}{"code": "ORDER_PLACED"}
			}
		}
	}
	return map[string]interface{}{"contract": c}
}

// buildOnCancel marks the contract as CANCELLED
func buildOnCancel(contract interface{}) map[string]interface{} {
	c := cloneMap(toMap(contract))
	c["status"] = map[string]interface{}{"code": "CANCELLED"}
	if perfs, ok := c["performance"].([]interface{}); ok {
		for _, p := range perfs {
			if pm, ok := p.(map[string]interface{}); ok {
				pm["status"] = map[string]interface{}{"code": "CANCELLED"}
			}
		}
	}
	if commitments, ok := c["commitments"].([]interface{}); ok {
		for _, cm := range commitments {
			if cmMap, ok := cm.(map[string]interface{}); ok {
				cmMap["status"] = map[string]interface{}{"descriptor": map[string]interface{}{"code": "CANCELLED"}}
			}
		}
	}
	return map[string]interface{}{"contract": c}
}

// buildOnSupport returns support contact info
func buildOnSupport(msg map[string]interface{}) map[string]interface{} {
	return map[string]interface{}{
		"support": map[string]interface{}{
			"phone": "+62-800-000-1234",
			"email": "support@ion-seller.id",
			"url":   "https://support.ion-seller.id",
			"hours": "Mon-Sat 09:00-21:00 WIB",
		},
	}
}

func enrichCommitmentPrices(c map[string]interface{}) {
	commitments, ok := c["commitments"].([]interface{})
	if !ok {
		return
	}
	for _, cm := range commitments {
		cmMap, ok := cm.(map[string]interface{})
		if !ok {
			continue
		}
		attrs, ok := cmMap["commitmentAttributes"].(map[string]interface{})
		if !ok {
			continue
		}
		if attrs["price"] == nil {
			attrs["price"] = map[string]interface{}{
				"value":    130000.0,
				"currency": "IDR",
			}
		}
	}
}

func setContractAttributes(c map[string]interface{}) {
	if c["contractAttributes"] == nil {
		c["contractAttributes"] = map[string]interface{}{
			"@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailContract/v2.1/context.jsonld",
			"@type":    "rcca:RetailContract",
		}
	}
}

func postToCaller(action string, payload BecknMsg) error {
	data, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}
	url := fmt.Sprintf("%s/%s", bppCallerURL, action)
	resp, err := http.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("post %s: %w", url, err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	log.Printf("[caller] POST %s → %d: %s", url, resp.StatusCode, string(respBody))
	return nil
}

func publishCatalog() error {
	catalog := map[string]interface{}{
		"context": map[string]interface{}{
			"version":       "2.0.0",
			"action":        "catalog/publish",
			"timestamp":     time.Now().UTC().Format(time.RFC3339),
			"messageId":     newUUID(),
			"transactionId": newUUID(),
			"bppId":         bppID,
			"bppUri":        bppURI,
			"ttl":           "PT30S",
			"networkId":     networkID,
		},
		"message": map[string]interface{}{
			"catalogs": []interface{}{
				buildCatalogEntry(
					time.Now().UTC().Format(time.RFC3339),
					time.Now().AddDate(1, 0, 0).UTC().Format(time.RFC3339),
				),
			},
		},
	}

	data, err := json.Marshal(catalog)
	if err != nil {
		return fmt.Errorf("marshal catalog: %w", err)
	}
	url := fmt.Sprintf("%s/publish", bppCallerURL)
	resp, err := http.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("post publish: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	log.Printf("[publish] POST %s → %d: %s", url, resp.StatusCode, string(body))
	return nil
}

// --- Helpers ---

func cloneCtx(ctx map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(ctx))
	for k, v := range ctx {
		out[k] = v
	}
	return out
}

func deepGet(m map[string]interface{}, key string) interface{} {
	if m == nil {
		return nil
	}
	return m[key]
}

func toMap(v interface{}) map[string]interface{} {
	if m, ok := v.(map[string]interface{}); ok {
		return m
	}
	return map[string]interface{}{}
}

// cloneMap does a shallow clone of the map, with a deep clone of slices one level deep
func cloneMap(m map[string]interface{}) map[string]interface{} {
	data, _ := json.Marshal(m)
	var out map[string]interface{}
	json.Unmarshal(data, &out)
	return out
}

// newUUID generates a v4-style UUID using time and random bytes
func newUUID() string {
	return fmt.Sprintf("%x-%x-%x-%x-%x",
		time.Now().UnixNano()&0xffffffff,
		time.Now().UnixNano()>>32&0xffff,
		(time.Now().UnixNano()>>48&0x0fff)|0x4000,
		(time.Now().UnixNano()>>56&0x3fff)|0x8000,
		time.Now().UnixNano()&0xffffffffffff,
	)
}
