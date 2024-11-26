// Import contract configuration from contractConfig.js
import { contractABI, contractAddress } from "./contractConfig.js";

var web3;
var contractInstance;

async function connect() {
    if (window.ethereum) {
        web3 = new Web3(window.ethereum);
        try {
            // Request account access if needed
            await window.ethereum.request({ method: "eth_requestAccounts" });
            console.log("MetaMask connected");

            // Initialize the contract instance using the imported ABI and address
            contractInstance = new web3.eth.Contract(contractABI, contractAddress);
            console.log("Contract instance initialized");
        } catch (error) {
            console.error("User denied account access", error);
        }
    } else {
        alert("Please install MetaMask to use this application.");
    }
}

window.onload = connect; // Connect when the window loads



