export async function validateAccess(requiredRole) {
    try {
        // Retrieve session data from localStorage
        const sessionToken = localStorage.getItem("sessionToken");
        const userRole = localStorage.getItem("userRole");
        const loggedInAddress = localStorage.getItem("loggedInAddress");

        // Check if session data exists
        if (!sessionToken || !userRole || !loggedInAddress) {
            alert("Unauthorized access. Please log in.");
            location.href = "./index.html"; // Redirect to login page
            return false;
        }

        // Check if the user role matches the required role
        if (userRole !== requiredRole) {
            alert("Unauthorized role. Access denied.");
            location.href = "./index.html"; // Redirect to login page
            return false;
        }

        // Validate the logged-in MetaMask address
        const accounts = await window.ethereum.request({ method: "eth_accounts" });
        if (accounts.length === 0 || accounts[0] !== loggedInAddress) {
            alert("MetaMask address mismatch. Please log in with the correct account.");
            location.href = "./index.html"; // Redirect to login page
            return false;
        }

        // Session and role validation passed
        return true;

    } catch (error) {
        console.error("Error validating access:", error);
        alert("An error occurred during validation. Please log in again.");
        location.href = "./index.html"; // Redirect to login page
        return false;
    }
}
