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

    event AgentAdded(address indexed agent, string name, uint256 age, uint256 designation);
    event AccessRequested(address indexed patient, address indexed doctor);
    event AccessGranted(address indexed doctor, address indexed patient);
    event AccessRevoked(address indexed patient, address indexed doctor);
    event MedicalRecordAdded(address indexed patient, string diagnosis, string ipfsHash);
    event MedicalRecordUpdated(address indexed patient, uint256 index, string newDescription);

    // Function to add a patient or doctor
    function add_agent(
        string memory _name,
        uint256 _age,
        uint256 _designation,
        string memory _hash
    ) public returns (string memory) {
        address addr = msg.sender;

        if (_designation == 0) {
            require(bytes(patientInfo[addr].name).length == 0, "Patient already registered");
            Patient storage patient = patientInfo[addr];
            patient.name = _name;
            patient.age = _age;
            patient.recordHash = _hash;
            patientList.push(addr);
        } else if (_designation == 1) {
            require(bytes(doctorInfo[addr].name).length == 0, "Doctor already registered");
            Doctor storage doctor = doctorInfo[addr];
            doctor.name = _name;
            doctor.age = _age;
            doctorList.push(addr);
        } else {
            revert("Invalid designation");
        }

        emit AgentAdded(addr, _name, _age, _designation);
        return _name;
    }

    // Function to create a medical record for a patient (Doctor)
    function addRecordByDoctor(address patientAddr, string memory _diagnosis, string memory _ipfsHash) public {
        require(bytes(doctorInfo[msg.sender].name).length > 0, "Caller is not a registered doctor");
        require(bytes(patientInfo[patientAddr].name).length > 0, "Patient does not exist");
        require(isAccessGranted(patientAddr, msg.sender), "Doctor does not have access to this patient");

        Patient storage patient = patientInfo[patientAddr];
        patient.records.push(
            MedicalRecord({
                diagnosis: _diagnosis,
                ipfsHash: _ipfsHash,
                timestamp: block.timestamp
            })
        );

        emit MedicalRecordAdded(patientAddr, _diagnosis, _ipfsHash);
    }

    // Function to edit a medical record (Doctor)
    function editMedicalRecord(address patientAddr, uint256 index, string memory newDescription) public {
        require(bytes(doctorInfo[msg.sender].name).length > 0, "Caller is not a registered doctor");
        require(bytes(patientInfo[patientAddr].name).length > 0, "Patient does not exist");
        require(isAccessGranted(patientAddr, msg.sender), "Doctor does not have access to this patient");
        require(index < patientInfo[patientAddr].records.length, "Invalid record index");

        patientInfo[patientAddr].records[index].ipfsHash = newDescription;

        emit MedicalRecordUpdated(patientAddr, index, newDescription);
    }

    // **New Function**: Allow patients to add their own medical records
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

        emit MedicalRecordAdded(msg.sender, _diagnosis, _ipfsHash);
    }

    // **New Function**: Allow patients to edit their own medical records
    function editPatientRecord(uint256 index, string memory newDescription) public {
        require(bytes(patientInfo[msg.sender].name).length > 0, "Caller is not a registered patient");
        require(index < patientInfo[msg.sender].records.length, "Invalid record index");

        patientInfo[msg.sender].records[index].ipfsHash = newDescription;

        emit MedicalRecordUpdated(msg.sender, index, newDescription);
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

    // Request access from a patient to a doctor
    function request_access(address doctorAddr) public {
        require(bytes(doctorInfo[doctorAddr].name).length > 0, "Doctor does not exist");
        require(!accessRequests[msg.sender][doctorAddr], "Request already pending");
        require(!isAccessGranted(msg.sender, doctorAddr), "Access already granted");

        accessRequests[msg.sender][doctorAddr] = true;
        pendingRequests[doctorAddr].push(msg.sender);

        emit AccessRequested(msg.sender, doctorAddr);
    }

    // Accept access request
    function accept_access_request(address patientAddr) public {
        require(accessRequests[patientAddr][msg.sender], "No pending request from this patient");

        doctorInfo[msg.sender].patientAccessList.push(patientAddr);
        patientInfo[patientAddr].doctorAccessList.push(msg.sender);

        accessRequests[patientAddr][msg.sender] = false;
        remove_pending_request(msg.sender, patientAddr);

        emit AccessGranted(msg.sender, patientAddr);
    }

    // Reject access request
    function reject_access_request(address patientAddr) public {
        require(accessRequests[patientAddr][msg.sender], "No pending request from this patient");

        accessRequests[patientAddr][msg.sender] = false;
        rejectedRequests[patientAddr][msg.sender] = true;
        remove_pending_request(msg.sender, patientAddr);
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

        emit AccessRevoked(msg.sender, doctorAddr);
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
