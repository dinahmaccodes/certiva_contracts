#[starknet::contract]
pub mod Certiva {
    use core::array::ArrayTrait;
    use core::byte_array::ByteArray;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, contract_address_const, get_caller_address};
    use starknet::class_hash::ClassHash;
    use crate::Interfaces::ICertiva::ICertiva;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_upgrades::interface::IUpgradeable;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);


    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        owner: ContractAddress,
        university: Map<ContractAddress, University>,
        certificates: Map<felt252, Certificate>,
        is_paused: bool,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        assert(owner != contract_address_const::<0>(), 'Owner cannot be zero address');
        self.ownable.initializer(owner);
    }

    #[derive(Drop, Serde, starknet::Event, starknet::Store)]
    pub struct University {
        pub university_name: felt252,
        pub website_domain: ByteArray,
        pub country: felt252,
        pub accreditation_body: felt252,
        pub university_email: ByteArray,
        pub wallet_address: ContractAddress,
    }

    #[derive(Drop, Clone, Serde, starknet::Event, starknet::Store)]
    pub struct Certificate {
        pub certificate_meta_data: ByteArray,
        pub hashed_key: ByteArray,
        pub certificate_id: felt252,
        pub issuer_domain: ByteArray,
        pub issuer_address: ContractAddress,
        pub isActive: bool,
    }

    #[derive(Drop, Serde, starknet::Event)]
    pub struct BulkCertificatesIssued {
        pub count: felt252,
        pub issuer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CertificateFound {
        pub issuer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CertificateNotFound {
        pub issuer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CertificateRevoked {
        pub certificate_id: felt252,
        pub issuer: ContractAddress,
        pub reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PausedContract {
        pub is_paused: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct UnpausedContract {
        pub is_paused: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        university_created: University,
        certificate_issued: Certificate,
        certificates_bulk_issued: BulkCertificatesIssued,
        CertificateFound: CertificateFound,
        CertificateNotFound: CertificateNotFound,
        CertificateRevoked: CertificateRevoked,
        PausedContract: PausedContract,
        UnpausedContract: UnpausedContract,
         #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[abi(embed_v0)]
    impl CertivaImpl of ICertiva<ContractState> {
        // fn to register university
        // only contract owner can register university
        fn register_university(
            ref self: ContractState,
            university_name: felt252,
            website_domain: ByteArray,
            country: felt252,
            accreditation_body: felt252,
            university_email: ByteArray,
            wallet_address: ContractAddress,
        ) {
            // Ensure the contract is not paused
            self.assert_not_paused();

            // Check that caller is the owner
            let caller = get_caller_address();
            let owner = self.owner.read();
            let zero_address = contract_address_const::<0>();
            assert(caller == owner, 'Unauthorized caller');

            // Validate inputs
            assert(university_name != 0, 'University name is required');
            assert(wallet_address != zero_address, 'Wallet address cannot be zero');
            assert(country != 0, 'Country is required');

            let new_university = University {
                university_name: university_name,
                website_domain: website_domain.clone(),
                country: country,
                accreditation_body: accreditation_body,
                university_email: university_email.clone(),
                wallet_address: wallet_address,
            };

            self.university.write(wallet_address, new_university);

            self
                .emit(
                    Event::university_created(
                        University {
                            university_name,
                            website_domain,
                            country,
                            accreditation_body,
                            university_email,
                            wallet_address,
                        },
                    ),
                );
        }

        // Function to get university details by wallet address
        fn get_university(self: @ContractState, wallet_address: ContractAddress) -> University {
            self.university.read(wallet_address)
        }

        // Function to issue a certificate by a registered university
        fn issue_certificate(
            ref self: ContractState,
            certificate_meta_data: ByteArray,
            hashed_key: ByteArray,
            certificate_id: felt252,
        ) {
            // Ensure the contract is not paused
            self.assert_not_paused();

            let caller = get_caller_address();

            let university = self.university.read(caller);
            let zero_address = contract_address_const::<0>();
            assert(university.wallet_address != zero_address, 'University not registered');

            let new_certificate = Certificate {
                certificate_meta_data: certificate_meta_data.clone(),
                hashed_key: hashed_key.clone(),
                certificate_id: certificate_id.clone(),
                issuer_domain: university.website_domain.clone(),
                issuer_address: caller,
                isActive: true,
            };

            self.certificates.write(certificate_id, new_certificate.clone());
            self.emit(Event::certificate_issued(new_certificate));
        }

        // Function to issue multiple certificates at once by a registered university
        fn bulk_issue_certificates(
            ref self: ContractState,
            certificate_meta_data_array: Array<ByteArray>,
            hashed_key_array: Array<ByteArray>,
            certificate_id_array: Array<felt252>,
        ) {
            // Ensure the contract is not paused
            self.assert_not_paused();

            let caller = get_caller_address();

            let university = self.university.read(caller);
            let zero_address = contract_address_const::<0>();
            assert(university.wallet_address != zero_address, 'University not registered');

            let len = certificate_id_array.len();
            assert(certificate_meta_data_array.len() == len, 'Arrays length mismatch');
            assert(hashed_key_array.len() == len, 'Arrays length mismatch');

            let mut i: u32 = 0;
            while i != len {
                let certificate_meta_data = certificate_meta_data_array.at(i).clone();
                let hashed_key = hashed_key_array.at(i).clone();
                let certificate_id = certificate_id_array.at(i).clone();

                let new_certificate = Certificate {
                    certificate_meta_data: certificate_meta_data,
                    hashed_key: hashed_key,
                    certificate_id: certificate_id,
                    issuer_domain: university.website_domain.clone(),
                    issuer_address: caller,
                    isActive: true,
                };

                self.certificates.write(certificate_id, new_certificate);

                i += 1;
            }

            let count_felt: felt252 = len.into();

            self
                .emit(
                    Event::certificates_bulk_issued(
                        BulkCertificatesIssued { count: count_felt, issuer: caller },
                    ),
                );
        }

        // Function to get certificate details by certificate ID
        fn get_certificate_by_id(self: @ContractState, certificate_id: felt252) -> Certificate {
            let certificate: Certificate = self.certificates.read(certificate_id);
            // Check if the certificate exists
            assert(certificate.certificate_id == certificate_id, 'Certificate not found');
            certificate
        }

        // Function to get Certificate details by issuer address
        fn get_certicate_by_issuer(ref self: ContractState) -> Array<Certificate> {
            let caller = get_caller_address();
            let mut certificates_by_issuer: Array<Certificate> = ArrayTrait::new();
            let mut found: bool = false;

            let mut i: usize = 1;
            let max_iterations: usize = 101;
            while i != max_iterations {
                let certificate = self.certificates.read(i.into());
                if certificate.issuer_address == caller {
                    certificates_by_issuer.append(certificate);
                    found = true;
                }

                i = i + 1;
            }

            if found {
                self.emit(Event::CertificateFound(CertificateFound { issuer: caller }));
            } else {
                self.emit(Event::CertificateNotFound(CertificateNotFound { issuer: caller }));
            }

            certificates_by_issuer
        }

        fn verify_certificate(
            ref self: ContractState, certificate_id: felt252, hashed_key: ByteArray,
        ) -> bool {
            // Ensure the contract is not paused
            self.assert_not_paused();

            let certificate = self.certificates.read(certificate_id);

            if certificate.hashed_key != hashed_key {
                return false;
            }

            if certificate.isActive {
                return true;
            } else {
                let reason: felt252 = 'Certificate has been revoked';
                self
                    .emit(
                        Event::CertificateRevoked(
                            CertificateRevoked {
                                certificate_id: certificate_id,
                                issuer: certificate.issuer_address,
                                reason: reason,
                            },
                        ),
                    );
                return false;
            }
        }

        fn revoke_certificate(
            ref self: ContractState, certificate_id: felt252,
        ) -> Result<(), felt252> {
            // Ensure the contract is not paused
            self.assert_not_paused();

            let caller = get_caller_address();

            // Check if caller is a registered university
            let university = self.university.read(caller);
            let zero_address = contract_address_const::<0>();
            if university.wallet_address == zero_address {
                return Result::Err('University not registered');
            }

            // Get certificate and verify it exists
            let mut certificate = self.certificates.read(certificate_id);
            if certificate.certificate_id == 0 {
                return Result::Err('Certificate not found');
            }

            // Verify the caller is the issuer and domains match
            if certificate.issuer_address != caller {
                return Result::Err('Not certificate issuer');
            }
            if certificate.issuer_domain != university.website_domain {
                return Result::Err('Domain mismatch');
            }

            // Revoke the certificate
            certificate.isActive = false;
            self.certificates.write(certificate_id, certificate);

            // Emit event
            let reason: felt252 = 'Certificate has been revoked';
            self
                .emit(
                    Event::CertificateRevoked(
                        CertificateRevoked { certificate_id, issuer: caller, reason: reason },
                    ),
                );

            Result::Ok(())
        }

        fn pause_contract(ref self: ContractState) {
            // Ensure the contract can only be called by owner
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Not the owner');
            // Check if contract has been paused
            assert(!self.is_paused.read(), 'Contract is paused already');
            // Set paused state to true
            self.is_paused.write(true);
            // Emit event
            self.emit(Event::PausedContract(PausedContract { is_paused: true }));
        }

        fn unpause_contract(ref self: ContractState) {
            // Ensure only owner can unpause contract
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Not the owner');

            // Change pause state to false
            self.is_paused.write(false);
            // Emit event
            self.emit(Event::UnpausedContract(UnpausedContract { is_paused: false }));
        }

        fn check_if_paused(self: @ContractState) -> bool {
            self.is_paused.read()
        }
    }

    #[generate_trait]
    pub impl Internal of InternalTrait {
        // this is where the internal functions are defined
        // Internal view functions are used to check state of contract
        // Takes `@self` as it only needs to read state
        // Can only be called by other functions within the contract
        fn assert_not_paused(self: @ContractState) {
            assert(!self.is_paused.read(), 'Contract is paused already');
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
