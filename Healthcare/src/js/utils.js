let web3;
let contractInstance;

// Initialize Web3 and Contract
async function initializeWeb3() {
    if (!window.ethereum) {
        alert("Please install MetaMask to use this application.");
        location.href = "./index.html";
        return false;
    }

    try {
        if (!web3) {
            web3 = new Web3(window.ethereum);
            await window.ethereum.request({ method: "eth_requestAccounts" });
            contractInstance = new web3.eth.Contract(contractABI, contractAddress);
            console.log("Web3 and contract initialized.");
        }
        return true;
    } catch (error) {
        console.error("Error connecting to MetaMask:", error);
        alert("Failed to connect to MetaMask.");
        return false;
    }
}

// Validate Login
async function validateLogin() {
    if (!web3 || !contractInstance) {
        await initializeWeb3();
    }

    const accounts = await web3.eth.getAccounts();
    const publicKey = accounts[0];

    if (!publicKey) {
        alert("No MetaMask account found. Please log in to MetaMask.");
        throw new Error("MetaMask account not found");
    }

    const loggedInUser = sessionStorage.getItem("loggedInUser");
    if (loggedInUser && loggedInUser !== publicKey) {
        alert("Session mismatch detected. Please log in again.");
        sessionStorage.clear();
        location.href = "./index.html";
        throw new Error("Session mismatch");
    }

    sessionStorage.setItem("loggedInUser", publicKey);
}

// Validate Role
async function validateRole(expectedRole) {
    await validateLogin();

    const accounts = await web3.eth.getAccounts();
    const publicKey = accounts[0];

    try {
        if (expectedRole === "admin") {
            const isAdmin = await contractInstance.methods.checkAdmin(publicKey).call();
            if (!isAdmin) throw new Error("Access denied. Admin role required.");
        } else if (expectedRole === "patient") {
            const patient = await contractInstance.methods.get_patient(publicKey).call();
            const patientName = patient[0]; // Patient name
            const patientAge = patient[1]; // Patient age
            if (!patientName || patientAge === "0") throw new Error("Access denied. Patient role required.");
        } else if (expectedRole === "doctor") {
            const doctor = await contractInstance.methods.get_doctor(publicKey).call();
            const doctorName = doctor[0]; // Doctor name
            const doctorAge = doctor[1]; // Doctor age
            if (!doctorName || doctorAge === "0") throw new Error("Access denied. Doctor role required.");
        }
        console.log(`${expectedRole.charAt(0).toUpperCase() + expectedRole.slice(1)} verified.`);
        return true;
    } catch (error) {
        console.error("Error validating role:", error);
        alert(error.message);
        location.href = "./index.html";
        return false;
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
                const isAdmin = await contractInstance.methods.checkAdmin(publicKey).call();
                if (isAdmin) {
                    await contractInstance.methods.log_admin_logout().send({ from: publicKey });
                    console.log("Admin logged out.");
                } else {
                    const patient = await contractInstance.methods.get_patient(publicKey).call();
                    if (patient[0]) {
                        await contractInstance.methods.log_patient_logout().send({ from: publicKey });
                        console.log("Patient logged out successfully.");
                    } else {
                        const doctor = await contractInstance.methods.get_doctor(publicKey).call();
                        if (doctor[0]) {
                            await contractInstance.methods.log_doctor_logout().send({ from: publicKey });
                            console.log("Doctor logged out successfully.");
                        } else {
                            console.error("Unrecognized user role.");
                            alert("Unrecognized user role. Unable to log out.");
                            return;
                        }
                    }
                }
            } catch (error) {
                console.error("Error during logout:", error);
            }

            sessionStorage.clear();
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
