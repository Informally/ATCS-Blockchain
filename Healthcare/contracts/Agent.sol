// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Agent {
    struct MedicalRecord {
        string diagnosis;
        string ipfsHash;
        uint256 timestamp;
    }

    struct Patient {
        string name;
        uint256 age;
        address[] doctorAccessList;
        MedicalRecord[] records;
        string recordHash; // Placeholder for external patient data
    }

    struct Doctor {
        string name;
        uint256 age;
        address[] patientAccessList;
    }

    uint256 creditPool;
    address[] public patientList;
    address[] public doctorList;

    mapping(address => Patient) private patientInfo;
    mapping(address => Doctor) private doctorInfo;

    mapping(address => mapping(address => bool)) public accessRequests;
    mapping(address => mapping(address => bool)) public rejectedRequests;

    mapping(address => address[]) public pendingRequests;

    address[] public pendingPatientApprovals;
    address[] public pendingDoctorApprovals;
    
    mapping(address => bool) public isPendingPatientApproval;
    mapping(address => bool) public isPendingDoctorApproval;

    mapping(address => string) public pendingNames;
    mapping(address => uint256) public pendingAges;

    // Admin address
    address public adminAddress;

    bool public requireApprovalForRoleSwitch = true; // Default: approval required

    // Authentication fee and logout fee (settable by admin)
    uint256 public authenticationFee = 0.01 ether;
    uint256 public logoutFee = 0.005 ether;

    event AgentAdded(address indexed agent, string name, uint256 age, uint256 designation);
    event AccessRequested(address indexed patient, address indexed doctor, uint256 timestamp);
    event AccessGranted(address indexed doctor, address indexed patient, uint256 timestamp);
    event AccessRejected(address indexed doctor, address indexed patient, uint256 timestamp);
    event AccessRevoked(address indexed patient, address indexed doctor, uint256 timestamp);
    event MedicalRecordAdded(address indexed patient, string diagnosis, string ipfsHash, address addedBy, uint256 timestamp);
    event MedicalRecordEdited(address indexed patient, uint256 index, string newDescription, address editedBy, string editedByName, uint256 timestamp);
    event PatientLoggedIn(address indexed patient, string name, uint256 timestamp);
    event PatientLoggedOut(address indexed patient, string name, uint256 timestamp);
    event DoctorLoggedIn(address indexed doctor, string name, uint256 timestamp);
    event DoctorLoggedOut(address indexed doctor, string name, uint256 timestamp);
    event RegistrationRequested(address indexed user, string name, uint256 designation, uint256 timestamp);
    event RegistrationApproved(address indexed user, uint256 designation, uint256 timestamp);
    event RegistrationRejected(address indexed user, uint256 designation, uint256 timestamp);
    event AdminAuthenticated(address indexed admin, uint256 timestamp, uint256 feePaid);
    event AdminLoggedOut(address indexed admin, uint256 timestamp, uint256 feePaid);

    constructor() {
        adminAddress = msg.sender; // Set the deployer's address as the admin
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "Caller is not an admin");
        _;
    }

        // Set authentication and logout fees
    function setAuthenticationFee(uint256 fee) public onlyAdmin {
        authenticationFee = fee;
    }

    function setLogoutFee(uint256 fee) public onlyAdmin {
        logoutFee = fee;
    }

    // Admin authentication with fee
    function log_admin_authentication() public payable {
        require(msg.sender == adminAddress, "Caller is not the admin");
        require(msg.value == authenticationFee, "Incorrect fee sent for authentication");

        emit AdminAuthenticated(msg.sender, block.timestamp, msg.value);
    }

    // Admin logout with fee
    function log_admin_logout() public payable {
        require(msg.sender == adminAddress, "Caller is not the admin");
        require(msg.value == logoutFee, "Incorrect fee sent for logout");

        emit AdminLoggedOut(msg.sender, block.timestamp, msg.value);
    }

    // Withdraw collected funds
    function withdrawFunds() public onlyAdmin {
        payable(adminAddress).transfer(address(this).balance);
    }

    // Add new admin function (only the current admin can add new admins)
    function add_admin(address newAdmin) public onlyAdmin {
        adminAddress = newAdmin; // Change the admin to the new address
    }

    // Check if the user is an admin
    function checkAdmin(address user) public view returns (bool) {
        return user == adminAddress;
    }
    
    function setApprovalRequirementForRoleSwitch(bool _requireApproval) public onlyAdmin {
    requireApprovalForRoleSwitch = _requireApproval;
    }

    // Modified add_agent_request to include name and age
    function add_agent_request(string memory _name, uint256 _age, uint256 _designation) public {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_age > 0, "Age must be greater than zero");

        if (_designation == 0) {
            require(bytes(patientInfo[msg.sender].name).length == 0, "Patient already registered");
            require(!isPendingPatientApproval[msg.sender], "Request already submitted");

            pendingPatientApprovals.push(msg.sender);
            isPendingPatientApproval[msg.sender] = true;
        } else if (_designation == 1) {
            require(bytes(doctorInfo[msg.sender].name).length == 0, "Doctor already registered");
            require(!isPendingDoctorApproval[msg.sender], "Request already submitted");

            pendingDoctorApprovals.push(msg.sender);
            isPendingDoctorApproval[msg.sender] = true;
        } else {
            revert("Invalid designation");
        }

        pendingNames[msg.sender] = _name;
        pendingAges[msg.sender] = _age;

        emit RegistrationRequested(msg.sender, _name, _designation, block.timestamp);
    }

    // Approve registration function
    function approve_registration(
    address user,
    string memory _name,
    uint256 _age,
    uint256 _designation
) public onlyAdmin {
    require(bytes(_name).length > 0, "Name cannot be empty");
    require(_age > 0, "Age must be greater than zero");

    if (_designation == 0) { // Approve as Patient
        // Remove from doctor-related mappings/lists if currently a Doctor
        if (bytes(doctorInfo[user].name).length > 0) {
            removeElementFromArray(doctorList, user);
            delete doctorInfo[user];
        }

        // Remove from pending doctor approvals if present
        if (isPendingDoctorApproval[user]) {
            isPendingDoctorApproval[user] = false;
            removePendingApproval(user, pendingDoctorApprovals);
        }

        // Prevent duplicate registration as Patient
        if (bytes(patientInfo[user].name).length > 0) {
            revert("User is already a registered patient.");
        }

        // Add to patient list
        Patient storage patient = patientInfo[user];
        patient.name = _name;
        patient.age = _age;
        patientList.push(user);

        // Remove from pending patient approvals
        if (isPendingPatientApproval[user]) {
            isPendingPatientApproval[user] = false;
            removePendingApproval(user, pendingPatientApprovals);
        }

        emit RegistrationApproved(user, 0, block.timestamp);

    } else if (_designation == 1) { // Approve as Doctor
        // Remove from patient-related mappings/lists if currently a Patient
        if (bytes(patientInfo[user].name).length > 0) {
            removeElementFromArray(patientList, user);
            delete patientInfo[user];
        }

        // Remove from pending patient approvals if present
        if (isPendingPatientApproval[user]) {
            isPendingPatientApproval[user] = false;
            removePendingApproval(user, pendingPatientApprovals);
        }

        // Prevent duplicate registration as Doctor
        if (bytes(doctorInfo[user].name).length > 0) {
            revert("User is already a registered doctor.");
        }

        // Add to doctor list
        Doctor storage doctor = doctorInfo[user];
        doctor.name = _name;
        doctor.age = _age;
        doctorList.push(user);

        // Remove from pending doctor approvals
        if (isPendingDoctorApproval[user]) {
            isPendingDoctorApproval[user] = false;
            removePendingApproval(user, pendingDoctorApprovals);
        }

        emit RegistrationApproved(user, 1, block.timestamp);

    } else {
        revert("Invalid designation");
    }

    // Cleanup pending names and ages
    delete pendingNames[user];
    delete pendingAges[user];
}



    // Reject registration function
    function reject_registration(address user, uint256 _designation) public onlyAdmin {
        if (_designation == 0) {
            require(isPendingPatientApproval[user], "User not in pending approvals");
            isPendingPatientApproval[user] = false;
            removePendingApproval(user, pendingPatientApprovals);
        } else if (_designation == 1) {
            require(isPendingDoctorApproval[user], "User not in pending approvals");
            isPendingDoctorApproval[user] = false;
            removePendingApproval(user, pendingDoctorApprovals);
        } else {
            revert("Invalid designation");
        }

        delete pendingNames[user];
        delete pendingAges[user];

        emit RegistrationRejected(user, _designation, block.timestamp);
    }

    // Helper function to remove from pending list
    function removePendingApproval(address user, address[] storage list) private {
        uint256 length = list.length;
        for (uint256 i = 0; i < length; i++) {
            if (list[i] == user) {
                list[i] = list[length - 1];
                list.pop();
                break;
            }
        }
    }

    // Helper function to remove a user from the list
    function removeElementFromArray(address[] storage list, address user) private {
        uint256 length = list.length;
        for (uint256 i = 0; i < length; i++) {
            if (list[i] == user) {
                list[i] = list[length - 1]; // Replace with the last element
                list.pop(); // Remove the last element
                break;
            }
        }
    }

    // Get pending patient registrations
    function get_pending_patient_approvals() public view onlyAdmin returns (address[] memory) {
        return pendingPatientApprovals;
    }

    // Get pending doctor registrations
    function get_pending_doctor_approvals() public view onlyAdmin returns (address[] memory) {
        return pendingDoctorApprovals;
    }

    // Modify editMedicalRecord function
    function editMedicalRecord(address patientAddr, uint256 index, string memory newDescription) public {
        require(bytes(doctorInfo[msg.sender].name).length > 0, "Caller is not a registered doctor");
        require(bytes(patientInfo[patientAddr].name).length > 0, "Patient does not exist");
        require(isAccessGranted(patientAddr, msg.sender), "Doctor does not have access to this patient");
        require(index < patientInfo[patientAddr].records.length, "Invalid record index");

        patientInfo[patientAddr].records[index].ipfsHash = newDescription;

        // Emit the doctor's name and address
        emit MedicalRecordEdited(patientAddr, index, newDescription, msg.sender, doctorInfo[msg.sender].name, block.timestamp);
    }

    function addRecordByPatient(string memory _diagnosis, string memory _ipfsHash) public {
        require(bytes(patientInfo[msg.sender].name).length > 0, "Caller is not a registered patient");

        Patient storage patient = patientInfo[msg.sender];
        patient.records.push(
            MedicalRecord({
                diagnosis: _diagnosis,
                ipfsHash: _ipfsHash,
                timestamp: block.timestamp
            })
        );

        // Emit the event with the patient's address as addedBy
        emit MedicalRecordAdded(msg.sender, _diagnosis, _ipfsHash, msg.sender, block.timestamp);
    }

    function addRecordByDoctor(address patient, string memory title, string memory description) public {
        require(bytes(doctorInfo[msg.sender].name).length > 0, "Caller is not a registered doctor");
        require(isAccessGranted(patient, msg.sender), "Doctor does not have access to this patient");

        MedicalRecord memory newRecord = MedicalRecord({
            diagnosis: title,
            ipfsHash: description,
            timestamp: block.timestamp
        });

        patientInfo[patient].records.push(newRecord);

        emit MedicalRecordAdded(patient, title, description, msg.sender, block.timestamp);
    }


    // Modify editPatientRecord function
    function editPatientRecord(uint256 index, string memory newDescription) public {
        require(bytes(patientInfo[msg.sender].name).length > 0, "Caller is not a registered patient");
        require(index < patientInfo[msg.sender].records.length, "Invalid record index");

        patientInfo[msg.sender].records[index].ipfsHash = newDescription;

        string memory editedByName = patientInfo[msg.sender].name;

        emit MedicalRecordEdited(msg.sender, index, newDescription, msg.sender, editedByName, block.timestamp);
    }

    function getAgentName(address agentAddr) public view returns (string memory) {
        if (bytes(patientInfo[agentAddr].name).length > 0) {
            return patientInfo[agentAddr].name;
        }
        if (bytes(doctorInfo[agentAddr].name).length > 0) {
            return doctorInfo[agentAddr].name;
        }
        return "Unknown";
    }

    // Function to get medical records for a patient
    function getMedicalRecords(address patientAddr)
        public
        view
        returns (string[] memory, string[] memory, uint256[] memory)
    {
        Patient storage patient = patientInfo[patientAddr];
        uint256 recordCount = patient.records.length;

        string[] memory diagnoses = new string[](recordCount);
        string[] memory ipfsHashes = new string[](recordCount);
        uint256[] memory timestamps = new uint256[](recordCount);

        for (uint256 i = 0; i < recordCount; i++) {
            MedicalRecord storage record = patient.records[i];
            diagnoses[i] = record.diagnosis;
            ipfsHashes[i] = record.ipfsHash;
            timestamps[i] = record.timestamp;
        }

        return (diagnoses, ipfsHashes, timestamps);
    }

    // Get details of a patient
    function get_patient(address addr)
        public
        view
        returns (
            string memory,
            uint256,
            address[] memory,
            string memory
        )
    {
        Patient storage patient = patientInfo[addr];
        return (patient.name, patient.age, patient.doctorAccessList, patient.recordHash);
    }

    // Get details of a doctor
    function get_doctor(address addr)
        public
        view
        returns (string memory, uint256, address[] memory)
    {
        Doctor storage doctor = doctorInfo[addr];
        return (doctor.name, doctor.age, doctor.patientAccessList);
    }

    // Get all registered patients
    function get_patient_list() public view returns (address[] memory) {
        return patientList;
    }

    // Get all registered doctors
    function get_doctor_list() public view returns (address[] memory) {
        return doctorList;
    }

    // Log patient login
    function log_patient_login() public {
        require(bytes(patientInfo[msg.sender].name).length > 0, "Caller is not a registered patient");
        emit PatientLoggedIn(msg.sender, patientInfo[msg.sender].name, block.timestamp);
    }

    // Log patient logout
    function log_patient_logout() public {
        require(bytes(patientInfo[msg.sender].name).length > 0, "Caller is not a registered patient");
        emit PatientLoggedOut(msg.sender, patientInfo[msg.sender].name, block.timestamp);
    }

    // Log doctor login
    function log_doctor_login() public {
        require(bytes(doctorInfo[msg.sender].name).length > 0, "Caller is not a registered doctor");
        emit DoctorLoggedIn(msg.sender, doctorInfo[msg.sender].name, block.timestamp);
    }

    // Log doctor logout
    function log_doctor_logout() public {
        require(bytes(doctorInfo[msg.sender].name).length > 0, "Caller is not a registered doctor");
        emit DoctorLoggedOut(msg.sender, doctorInfo[msg.sender].name, block.timestamp);
    }

// Request access from a patient to a doctor
    function request_access(address doctorAddr) public {
        require(bytes(doctorInfo[doctorAddr].name).length > 0, "Doctor does not exist");
        require(!accessRequests[msg.sender][doctorAddr], "Request already pending");
        require(!isAccessGranted(msg.sender, doctorAddr), "Access already granted");

        accessRequests[msg.sender][doctorAddr] = true;
        pendingRequests[doctorAddr].push(msg.sender);

        emit AccessRequested(msg.sender, doctorAddr, block.timestamp);
    }

    // Accept access request
    function accept_access_request(address patientAddr) public {
        require(accessRequests[patientAddr][msg.sender], "No pending request from this patient");

        doctorInfo[msg.sender].patientAccessList.push(patientAddr);
        patientInfo[patientAddr].doctorAccessList.push(msg.sender);

        accessRequests[patientAddr][msg.sender] = false;
        remove_pending_request(msg.sender, patientAddr);

        emit AccessGranted(msg.sender, patientAddr, block.timestamp);
    }

    // Reject access request
    function reject_access_request(address patientAddr) public {
        require(accessRequests[patientAddr][msg.sender], "No pending request from this patient");

        accessRequests[patientAddr][msg.sender] = false;
        rejectedRequests[patientAddr][msg.sender] = true;
        remove_pending_request(msg.sender, patientAddr);

        emit AccessRejected(msg.sender, patientAddr, block.timestamp);
    }

    // Internal function to remove a pending request
    function remove_pending_request(address doctorAddr, address patientAddr) internal {
        uint256 length = pendingRequests[doctorAddr].length;
        for (uint256 i = 0; i < length; i++) {
            if (pendingRequests[doctorAddr][i] == patientAddr) {
                pendingRequests[doctorAddr][i] = pendingRequests[doctorAddr][length - 1];
                pendingRequests[doctorAddr].pop();
                break;
            }
        }
    }

    // Get pending access requests
    function get_access_requests(address doctorAddr) public view returns (address[] memory) {
        return pendingRequests[doctorAddr];
    }

    // Check granted access for a patient
    function get_accessed_doctorlist_for_patient(address patientAddr)
        public
        view
        returns (address[] memory)
    {
        return patientInfo[patientAddr].doctorAccessList;
    }

    // Check granted access for a doctor
    function get_accessed_patientlist_for_doctor(address doctorAddr)
        public
        view
        returns (address[] memory)
    {
        return doctorInfo[doctorAddr].patientAccessList;
    }

    // Permit access by a patient to a doctor
    function permit_access(address doctorAddr) public payable {
        require(msg.value == 2 ether, "Insufficient payment");

        creditPool += 2 ether;
        doctorInfo[doctorAddr].patientAccessList.push(msg.sender);
        patientInfo[msg.sender].doctorAccessList.push(doctorAddr);
    }


    // Revoke access
    function revoke_access(address doctorAddr) public {
        remove_patient(msg.sender, doctorAddr);
        creditPool -= 2 ether;

        emit AccessRevoked(msg.sender, doctorAddr, block.timestamp);
    }

    // Internal function to remove access between a patient and doctor
    function remove_patient(address patientAddr, address doctorAddr) public {
        remove_element_in_array(doctorInfo[doctorAddr].patientAccessList, patientAddr);
        remove_element_in_array(patientInfo[patientAddr].doctorAccessList, doctorAddr);
    }

// Internal helper to remove an element from an array
    function remove_element_in_array(address[] storage array, address addr) internal {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; i++) {
            if (array[i] == addr) {
                array[i] = array[length - 1];
                array.pop();
                break;
            }
        }
    }

    // Check if access is granted
    function isAccessGranted(address patientAddr, address doctorAddr) internal view returns (bool) {
        address[] memory grantedDoctors = patientInfo[patientAddr].doctorAccessList;
        for (uint256 i = 0; i < grantedDoctors.length; i++) {
            if (grantedDoctors[i] == doctorAddr) {
                return true;
            }
        }
        return false;
    }
}