# LMA1980

I will use this Github page to document the incubator project I am hoping to conceive.

## Jero-Mu (제로 무)

An incubator project for a distributed application model, I will attempt to write it in Rust or in C#, and any other appropriate language to work with this solution.

### api.jelomu.local

A Rocket (v0.6-dev) integration to provide a distributable WebAPI.
 - /about
    - Provides runtime information on the current runtime.
 - Still a work in progress

The goal will be to support both public and mTLS authenticated requests. [planned]
 - The idea is to provide the end-users the guide-lines to generate CSR for gaining access.
 - Document the steps required by the operator to support mTLS server-side.
 - Establish usage policy.
 - Still require to authenticate the client user with either
    - Username / Password or Passphrase
    - Short lived Token
  
Provide an authentication mechanism [planned]
 - Use the host own public key to encrypt the password: forcing decryption by the host private key.
 - Use a username@realm-identifier
 - Return default role along with an associated session-token: minimal-authorized-access

Provide an authorization mechanism [planned]
 - A given user may have access to one or many role
 - minimal-authorized-access provides the following policy
    - get-about
    - get-about-detailed
    - ...
  - anonymous-access provides the following policy (applies to tokenless requests)
     - get-about
     - ...

### neuron-rs (neuron)

A minimal distributed compute unit: the idea is to be able to support links to resources. No transport involved at this level.

[milestone-1](neuron-rs/milestone-1.md)

### neuron-runner-rs (neuron-runner)[planned]

A minimal runtime environment for neurons implementation. Transport layer to be determined.

## workspace-builder

A tool to help compile multiple ABI targets when building a cargo project.
