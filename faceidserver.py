from flask import Flask, request, jsonify
import json
from flask_cors import CORS
import os
import base64
import cbor2
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from certvalidator import CertificateValidator, ValidationContext
from asn1crypto import x509 as asn1_x509

import hashlib
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509 import load_pem_x509_certificate
from cryptography.x509 import ObjectIdentifier
from pyasn1.codec.der.decoder import decode as der_decode
from pyasn1.type.univ import OctetString, Sequence
from datetime import datetime


app = Flask(__name__)
CORS(app)

DATABASE_FILE = "database.txt"               # unrelated simple DB (kept)
DATA_FILE = "key_public_database.txt"        # where we store App Attest public keys

TEAM_ID = "4V88SAY77L"
BUNDLE_ID = "com.localface.faceid"
EXPECTED_APP_ID = f"{TEAM_ID}.{BUNDLE_ID}".encode("utf-8")
EXPECTED_RP_ID_HASH = hashlib.sha256(EXPECTED_APP_ID).digest()

challenge_store = {}

# -------------------
# Helpers
# -------------------
def b64url_decode(s: str) -> bytes:
    """URL-safe base64 decode with padding fix; accepts normal base64 too."""
    if not isinstance(s, str):
        raise TypeError("b64url_decode expects a string")
    s = s.replace("-", "+").replace("_", "/")
    pad = "=" * (-len(s) % 4)
    return base64.b64decode(s + pad)

def b64url_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")

# -------------------
# Attestation (registration) verification
# -------------------
def verify_x5c(att_stmt, decoded, key_id):
    print("starting verification")
    print(f"Looking for key_id: {key_id}")
    print(f"Challenge store keys: {list(challenge_store.keys())}")

    # Try direct lookup first
    challenge_bytes = challenge_store.get(key_id)

    # If not found, try converting spaces to + in stored keys
    if challenge_bytes is None:
        for stored_key in challenge_store.keys():
            if stored_key and stored_key.replace(' ', '+') == key_id:
                challenge_bytes = challenge_store[stored_key]
                print(f"Found match by replacing spaces in stored key: '{stored_key}' -> '{key_id}'")
                break

    print(f"Found challenge_bytes: {challenge_bytes is not None}")

    if challenge_bytes is None:
        raise ValueError(f"No challenge found for key_id: {key_id}")

    x5c_list = att_stmt['x5c']
    # check at least 2 certs
    if len(x5c_list) < 2:
        raise ValueError("x5c must contain at least 2 certs")

    # parse certs using asn1_x509 (for chain validation) and cryptography (for public key/extension)
    certs_as_asn1 = [asn1_x509.Certificate.load(cert) for cert in x5c_list]
    leaf_as_asn1 = certs_as_asn1[0]
    intermediates = certs_as_asn1[1:]

    # Load Apple App Attestation Root CA (PEM on disk)
    with open("Apple_App_Attestation_Root_CA.pem", "rb") as f:
        pem_data = f.read()
    root_cert_crypto = load_pem_x509_certificate(pem_data, backend=default_backend())
    root_der = root_cert_crypto.public_bytes(serialization.Encoding.DER)
    root_cert_asn1 = asn1_x509.Certificate.load(root_der)

    # Validate the chain using certvalidator
    context = ValidationContext(trust_roots=[root_cert_asn1])
    validator = CertificateValidator(leaf_as_asn1, intermediate_certs=intermediates, validation_context=context)
    validator.validate_usage(set(['digital_signature']))
    print("Certificate chain validated successfully.")

    # Reconstruct signed data from authData + SHA256(clientDataJSON)
    auth_data = decoded['authData']  # binary
    if not isinstance(auth_data, (bytes, bytearray)):
        raise ValueError("authData missing/invalid")
    auth_data = bytes(auth_data)

    # In your current flow you hashed the challenge directly.
    # To keep your foundation but align with Apple's nonce:
    # We'll pretend your "challenge_bytes" represents the clientDataJSON already serialized bytes.
    # If you actually pass clientDataJSON base64 from app, replace challenge_bytes with the decoded clientDataJSON and hash that.
    client_data_hash = hashlib.sha256(challenge_bytes).digest()
    signed_data = auth_data + client_data_hash

    # Use leaf cert public key + Apple nonce extension to verify the nonce
    leaf_cert_crypto = x509.load_der_x509_certificate(x5c_list[0], default_backend())
    public_key = leaf_cert_crypto.public_key()

    # 4. Verify nonce in credCert extension (OID: 1.2.840.113635.100.8.2)
    oid = ObjectIdentifier("1.2.840.113635.100.8.2")
    ext = leaf_cert_crypto.extensions.get_extension_for_oid(oid)
    ext_value = ext.value.value  # DER-encoded value

    # The extension usually encodes as SEQUENCE { OCTET STRING nonce }
    try:
        decoded_seq, _ = der_decode(ext_value, asn1Spec=Sequence())
        nonce_from_cert = decoded_seq.getComponentByPosition(0)
        nonce_from_cert_bytes = bytes(nonce_from_cert)
    except Exception:
        # fallback to raw
        nonce_from_cert_bytes = ext_value

    expected_nonce = hashlib.sha256(signed_data).digest()
    if nonce_from_cert_bytes != expected_nonce and OctetString(expected_nonce) != nonce_from_cert:
        raise ValueError("Nonce does not match expected value")
    print("Nonce verified successfully.")

    # verify public key matches the key identifier from the app
    cred_cert = leaf_cert_crypto
    public_key = cred_cert.public_key()

    # Ensure it's an EC key and export in X9.62 uncompressed
    if hasattr(public_key, 'public_bytes'):
        uncompressed_point = public_key.public_bytes(
            encoding=serialization.Encoding.X962,
            format=serialization.PublicFormat.UncompressedPoint
        )
    else:
        raise TypeError("Public key is not an elliptic curve key")

    # compute sha-256 hash of the public key bytes
    key_id_computed = hashlib.sha256(uncompressed_point).digest()

    # compare to keyID from app (handle base64url or base64)
    try:
        keyID_from_app_bytes = b64url_decode(key_id)
    except Exception:
        keyID_from_app_bytes = base64.b64decode(key_id)

    if key_id_computed == keyID_from_app_bytes:
        print("key id match's public key")
    else:
        print("key id does not match cred cert public key")

    # Persist PEM (string) for later assertion verification
    public_key_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode('utf-8')

    entry = {
        # Keep your foundation: you're storing user “daniel” and using key_id as device_id
        "user_id": "daniel",
        "device_id": key_id,            # you used key_id here before; keeping it for continuity
        "public_key": public_key_pem,
        "timestamp": datetime.utcnow().isoformat()
    }

    # Check for duplicate public key for a different user (fix the bug: compare PEM string, not object; and defined user_id)
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE, "r") as f:
            for line in f:
                try:
                    existing = json.loads(line)
                    if existing.get("public_key") == public_key_pem and existing.get("user_id") != entry["user_id"]:
                        print("Error: Public key already registered to another user")
                        return
                except Exception:
                    continue

    # Save the entry
    with open(DATA_FILE, "a") as f:
        f.write(json.dumps(entry) + "\n")

    # Verify RP ID hash (first 32 bytes of authenticatorData)
    authenticator_data = decoded.get('authData')
    rp_id_hash = authenticator_data[:32]
    if rp_id_hash != EXPECTED_RP_ID_HASH:
        raise Exception("RP ID hash mismatch")
    print("app id hash match")

    # Counter must be zero for App Attest
    counter_bytes = authenticator_data[33:37]
    counter = int.from_bytes(counter_bytes, byteorder='big')
    print(f"Counter value: {counter}")
    if counter != 0:
        raise Exception("Authenticator data counter is not zero")
    print("Counter is zero as expected")

    # AAGUID checks
    aaguid_bytes = authenticator_data[37:53]
    print(aaguid_bytes)
    appattestdevelop = bytes.fromhex("617070617474657374646576656c6f70")  # "appattestdevelop"
    appattestprod = b'appattest' + b'\x00' * 7
    if aaguid_bytes == appattestdevelop:
        print("AAGUID matches development environment")
    elif aaguid_bytes == appattestprod:
        print("AAGUID matches production environment")
    else:
        raise Exception(f"AAGUID mismatch: {aaguid_bytes.hex()}")

    # 11. Verify credentialId == key_id
    credential_id_length = int.from_bytes(auth_data[53:55], 'big')
    credential_id = auth_data[55:55+credential_id_length]
    if credential_id != keyID_from_app_bytes:
        print("keyID " + key_id)
        print("cred_id " + credential_id.hex())
        raise ValueError("Credential ID does not match key_id")
    print("Credential ID verified successfully.")

    return True

# -------------------
# Storage lookup (fixing indentation bug)
# -------------------
def find_device_data(file_path, user_id, device_id):
    if not os.path.exists(file_path):
        return None
    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                print("Skipping invalid JSON line")
                continue
            if record.get("user_id") == user_id and record.get("device_id") == device_id:
                return record
    return None

# -------------------
# Assertion (message) verification – mirrors your attestation “foundation”
# -------------------
def verifyAssertion(assertion_bytes, client_data_obj, public_key_pem):
    """
    Keep your pattern:
      signed_data = authenticatorData || SHA256(clientDataJSON)
    Then verify ECDSA over that with the stored PEM public key.
    Also mirror the same RP ID / AAGUID / counter checks you did in attestation.
    """
    try:
        decoded = cbor2.loads(assertion_bytes)
        print("Decoded CBOR structure:", decoded)
    except Exception as e:
        print("failed to decode CBOR:", str(e))
        raise

    # Keys could be bytes or strings depending on encoder
    signature = decoded.get(b'signature') or decoded.get('signature')
    authenticator_data = decoded.get(b'authenticatorData') or decoded.get('authenticatorData')

    if not signature or not authenticator_data:
        raise ValueError("Malformed assertion: missing signature or authenticatorData")

    # Use EXACT JSON serialization (compact) to mirror app side
    client_data_bytes = json.dumps(client_data_obj, separators=(',', ':')).encode('utf-8')
    client_data_hash = hashlib.sha256(client_data_bytes).digest()

    signed_data = authenticator_data + client_data_hash

    # RP ID hash check (first 32 bytes)
    rp_id_hash = authenticator_data[:32]
    if rp_id_hash != EXPECTED_RP_ID_HASH:
        raise ValueError("RP ID hash mismatch (assertion)")

    # Counter must be zero for App Attest
    counter = int.from_bytes(authenticator_data[33:37], byteorder='big')
    if counter != 0:
        raise ValueError("Authenticator counter is not zero (assertion)")

    # AAGUID check (same offsets as in attestation)
    aaguid_bytes = authenticator_data[37:53]
    appattestdevelop = bytes.fromhex("617070617474657374646576656c6f70")
    appattestprod = b'appattest' + b'\x00' * 7
    if aaguid_bytes not in (appattestdevelop, appattestprod):
        raise ValueError(f"AAGUID mismatch (assertion): {aaguid_bytes.hex()}")

    # Verify signature (P-256 / ECDSA / SHA-256)
    pub = serialization.load_pem_public_key(public_key_pem.encode('utf-8'))
    pub.verify(signature, signed_data, ec.ECDSA(hashes.SHA256()))

    print("Assertion signature verified OK")
    return True

import urllib.parse

# -------------------
# Routes
# -------------------
@app.route('/appatest', methods=['POST', 'GET'])
def appatest():
    if request.method == 'GET':
        # Issue a challenge and (for continuity with your foundation) store by keyID if present
        challenge_bytes = os.urandom(32)
        key_id_raw = request.args.get('keyID')

        # The + character gets converted to space by URL decoding; convert back for base64
        key_id = key_id_raw.replace(' ', '+') if key_id_raw else None

        print(f"=== GET REQUEST ===")
        print(f"Raw keyid from URL: '{key_id_raw}'")
        print(f"Corrected keyid: '{key_id}'")

        # Keep the existing behavior: index by key_id. (You can switch to challengeId later.)
        challenge_store[key_id] = challenge_bytes
        challenge_b64 = base64.b64encode(challenge_bytes).decode('utf-8')

        return jsonify({
            'status': 'success',
            'challenge': challenge_b64
        })

    # POST: receive attestation object and verify (registration)
    if request.method == 'POST':
        data = request.get_json()
        print("Incoming JSON:", data)
        attestation_b64 = data.get('attestation')
        keyID = data.get('keyID')
        if not attestation_b64 or not keyID:
            return jsonify({"error": "Missing attestation or keyID"}), 400

        # Decode attestation (accept urlsafe or standard)
        try:
            try:
                attestation_bytes = b64url_decode(attestation_b64)
            except Exception:
                attestation_bytes = base64.b64decode(attestation_b64)
            decoded = cbor2.loads(attestation_bytes)
        except Exception as e:
            return jsonify({"error": "Failed to decode attestation", "details": str(e)}), 400

        att_stmt = decoded.get('attStmt')
        if not att_stmt:
            return jsonify({"error": "attStmt missing"}), 400

        print("keyid from post appatest " + keyID)

        try:
            verify_x5c(att_stmt, decoded, keyID)
        except Exception as e:
            return jsonify({"error": "Attestation verification failed", "details": str(e)}), 400

        return "Received", 200

@app.route('/verify', methods=['POST', 'GET'])
def verify():
    if request.method == 'GET':
        # Unrelated simple lookup kept as-is
        search_id = request.args.get('id')
        if not search_id:
            return jsonify({"status": "error", "message": "No ID specified"}), 400

        try:
            with open(DATABASE_FILE, "r") as f:
                stored_data = json.load(f)  # expect a list of dicts
        except FileNotFoundError:
            return jsonify({"status": "error", "message": "database.txt not found"}), 404
        except json.JSONDecodeError:
            return jsonify({"status": "error", "message": "Invalid JSON in database.txt"}), 400

        for obj in stored_data:
            if obj.get("ID") == search_id:
                return jsonify({"status": "ok", "message": obj.get("message"), "Name": obj.get("name"), "BirthDay": obj.get("dob")}), 200

        return jsonify({"status": "error", "message": f"No entry found with ID {search_id}"}), 404

    elif request.method == 'POST':
        # This is your message verification using the registered App Attest key
        new_data = request.get_json()
        if not new_data:
            return jsonify({"status": "ok", "received": new_data}), 200

        # You already send clientData fields inline; keep that foundation
        client_data = new_data.get('clientData', {})
        # We'll also accept keyID here to look up the stored key
        keyID = new_data.get('keyID')

        # Your custom payload fields (kept)
        challenge = client_data.get('challenge')
        message = client_data.get('message')
        user_id = client_data.get('ID') or "daniel"   # you stored "daniel" during attestation
        name_hash = client_data.get('name')
        dob_hash = client_data.get('dob')

        assertion_b64 = new_data.get('assertion')
        if not assertion_b64 or not keyID:
            return jsonify({"error": "Missing assertion or keyID"}), 400

        print("clientData (for message):", client_data)

        # Decode assertion (accept url-safe or standard base64)
        try:
            try:
                assertion_bytes = b64url_decode(assertion_b64)
            except Exception:
                assertion_bytes = base64.b64decode(assertion_b64)
        except Exception as e:
            return jsonify({"error": "Failed to decode assertion", "details": str(e)}), 400

        # Load stored public key (you stored device_id == key_id under user 'daniel')
        record = find_device_data(DATA_FILE, user_id="daniel", device_id=keyID)
        if not record:
            return jsonify({"error": "No stored key for this keyID/user"}), 404
        public_key_pem = record.get("public_key")
        if not public_key_pem:
            return jsonify({"error": "Stored record missing public_key"}), 500

        try:
            ok = verifyAssertion(assertion_bytes, client_data, public_key_pem)
            if not ok:
                return jsonify({"error": "Assertion verification failed"}), 400
        except Exception as e:
            return jsonify({"error": "Assertion verification threw", "details": str(e)}), 400

        return jsonify({"status": "ok", "verified": True, "message": "Signature valid", "payload_echo": {"message": message, "name": name_hash, "dob": dob_hash}}), 200

# -------------------
# Main
# -------------------
if __name__ == '__main__':
    # Ensure the App Attest key DB file exists
    if not os.path.exists(DATA_FILE):
        with open(DATA_FILE, "a"):
            pass
    app.run(host='0.0.0.0', port=5050, debug=True)
