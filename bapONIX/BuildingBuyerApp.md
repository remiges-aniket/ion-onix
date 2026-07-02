## Journey of Building and Testing a Buyer App
(Work in progress)

1. Identify a use case you want to work on and identify your role — buyer app or seller app (the rest of this document is for those who have identified their role as that of the Buyer).
2. Study examples related to your use case (if available). There might be many sets (if there are multiple patterns and variants). These examples will have a list of Beckn API message requests and responses along with their payload. Study these and understand the logical flow of information required to complete the transaction and the variants.
3. Install and configure the BAP ONIX adapter, then write your buyer-side logic against it — see `README.md` for the full setup guide. The adapter provides a `/bap/caller` endpoint where your software sends Beckn requests, and calls back your software through a webhook.
4. Test your software against either a sample BPP application, an available BPP on the sandbox network, or the bundled Postman collection (see the "Test with Postman" step in `README.md`).
5. Devlabs portal will have unit test case scripts for many patterns and variants. Test your software using those.
6. Devlabs portal also has complete flow test cases. Use those to test complete flows once the unit test cases are done.
7. Initiate onboarding to production through the ION Central portal.