let web3;
let contractInstance;

// Initialize Web3 and Contract
async function initializeWeb3() {
    if (!window.ethereum) {
        alert("Please install MetaMask to use this application.");
        location.href = "./index.html";
        throw new Error("MetaMask not installed.");
    }

    try {
        if (!web3) {
            web3 = new Web3(window.ethereum);
            console.log("Web3 initialized.");
        }

        // Request accounts only after session validation
        const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
        console.log("MetaMask connected:", accounts[0]);

        contractInstance = new web3.eth.Contract(contractABI, contractAddress);
        console.log("Contract instance initialized.");
    } catch (error) {
        console.error("Error initializing Web3:", error);
        alert("Failed to connect to MetaMask.");
        throw error;
    }
}

// Validate Login Session
async function validateLogin() {
    const sessionToken = localStorage.getItem("sessionToken");
    const loggedInAddress = localStorage.getItem("loggedInAddress");

    if (!sessionToken || !loggedInAddress) {
        alert("Access denied: You must log in through the login page.");
        sessionStorage.clear(); // Clear any leftover session
        localStorage.clear();
        location.href = "./index.html";
        throw new Error("Invalid session.");
    }

    if (!web3 || !contractInstance) {
        await initializeWeb3();
    }

    const accounts = await web3.eth.getAccounts();
    const activeAddress = accounts[0];

    // Ensure MetaMask address matches the logged-in session
    if (loggedInAddress !== activeAddress) {
        alert("Session mismatch detected. Please log in again.");
        sessionStorage.clear();
        localStorage.clear();
        location.href = "./index.html";
        throw new Error("Session mismatch.");
    }
    console.log("Login session validated successfully.");
}

// Validate User Role
async function validateRole(expectedRole) {
    await validateLogin();

    const accounts = await web3.eth.getAccounts();
    const publicKey = accounts[0];

    try {
        if (expectedRole === "doctor") {
            const doctor = await contractInstance.methods.get_doctor(publicKey).call();
            if (!doctor[0]) throw new Error("Access denied. Doctor role required.");
        } else if (expectedRole === "patient") {
            const patient = await contractInstance.methods.get_patient(publicKey).call();
            if (!patient[0]) throw new Error("Access denied. Patient role required.");
        } else if (expectedRole === "admin") {
            const isAdmin = await contractInstance.methods.checkAdmin(publicKey).call();
            if (!isAdmin) throw new Error("Access denied. Admin role required.");
        } else {
            throw new Error("Unsupported role.");
        }
        console.log(`Role '${expectedRole}' validated.`);
    } catch (error) {
        console.error("Error validating role:", error);
        alert(error.message);
        location.href = "./index.html";
        throw new Error("Role validation failed.");
    }
}

// Attach Logout
function attachLogout() {
    const logoutButton = document.getElementById("logoutButton");
    if (logoutButton) {
        logoutButton.addEventListener("click", async () => {
            const accounts = await web3.eth.getAccounts();
            const publicKey = accounts[0];

            try {
                // Attempt to determine the user's role
                if (await contractInstance.methods.checkAdmin(publicKey).call()) {
                    await contractInstance.methods.log_admin_logout().send({ from: publicKey });
                    console.log("Admin logged out.");
                } else if ((await contractInstance.methods.get_doctor(publicKey).call())[0]) {
                    await contractInstance.methods.log_doctor_logout().send({ from: publicKey });
                    console.log("Doctor logged out successfully.");
                } else if ((await contractInstance.methods.get_patient(publicKey).call())[0]) {
                    await contractInstance.methods.log_patient_logout().send({ from: publicKey });
                    console.log("Patient logged out successfully.");
                } else {
                    // If no roles match, explicitly log an error
                    console.error("Unrecognized user role. Unable to log out.");
                    alert("Unrecognized user role. Unable to log out.");
                    return;
                }
            } catch (error) {
                console.error("Error during logout:", error);
                alert("An error occurred during logout. Please try again.");
                return;
            }

            // Clear session storage and redirect to login page
            sessionStorage.clear();
            localStorage.clear();
            alert("Logged out successfully.");
            location.href = "./index.html";
        });
    } else {
        console.error("Logout button not found.");
    }
}


// Initialize Page
async function initializePage(expectedRole) {
    const web3Initialized = await initializeWeb3();
    if (!web3Initialized) throw new Error("Web3 initialization failed.");

    const roleValidated = await validateRole(expectedRole);
    if (roleValidated) {
        console.log("Page initialization complete.");
        return true;
    }
    throw new Error("Page initialization failed.");
}

// Fetch Agent Name
async function getAgentName(address) {
    if (!web3.utils.isAddress(address)) {
        console.error(`Invalid address: ${address}`);
        return "Unknown";
    }

    try {
        const name = await contractInstance.methods.getAgentName(address).call();
        return name || "Unknown";
    } catch (error) {
        console.error(`Error fetching agent name for address ${address}:`, error);
        return "Unknown";
    }
}
