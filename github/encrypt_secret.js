// https://docs.github.com/en/rest/reference/actions#create-or-update-an-organization-secret
const sodium = require('tweetsodium');

var myArgs = process.argv.slice(2);

//console.log(myArgs[0]);
//console.log(myArgs[1]);

const public_key = myArgs[0];
const value = myArgs[1];

// Convert the message and key to Uint8Array's (Buffer implements that interface)
const messageBytes = Buffer.from(value);
const keyBytes = Buffer.from(public_key, 'base64');

// Encrypt using LibSodium.
const encryptedBytes = sodium.seal(messageBytes, keyBytes);

// Base64 the encrypted secret
const encrypted = Buffer.from(encryptedBytes).toString('base64');

console.log(encrypted);
