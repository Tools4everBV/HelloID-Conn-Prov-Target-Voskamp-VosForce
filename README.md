# HelloID-Conn-Prov-Target-Voskamp-VosForce

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Voskamp-VosForce/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Voskamp-VosForce](#helloid-conn-prov-target-voskamp-vosforce)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
      - [Creating the Base64 Key from the `PKCS #12` Certificate](#creating-the-base64-key-from-the-pkcs-12-certificate)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Network access](#network-access)
    - [API permission errors](#api-permission-errors)
    - [Voskamp-VosForce API limitations](#voskamp-vosforce-api-limitations)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Voskamp-VosForce_ is a _target_ connector. _Voskamp-VosForce_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                            | Remarks                                                                          |
| ----------------------------------------- | --------- | -------------------------------------------------- | -------------------------------------------------------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Correlate, Update, Enable, Disable, Delete |                                                                                  |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                            |                                                                                  |
| **Resources**                             | ❌         | -                                                  |                                                                                  |
| **Entitlement Import: Accounts**          | ✅         | -                                                  | Only de API database is imported see [remark](#voskamp-vosforce-api-limitations) |
| **Entitlement Import: Permissions**       | ✅         | Roles permissions                                  | Only de API database is imported see [remark](#voskamp-vosforce-api-limitations) |
| **Governance Reconciliation Resolutions** | ✅         | -                                                  |                                                                                  |

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Voskamp-VosForce/refs/heads/main/Icon.png
```

### Requirements
- **Client certificate**: Obtain the PFX client certificate and password required for mutual TLS (mTLS).
- **API key**: Obtain an API key with permission to read and modify users, roles, and authorizations.
- **API URL**: Confirm the base URL for the tenant, for example `https://101.<customerName>.nl`.
- **Base64 Key**: Generate the base64-encoded key for the `PKCS #12` certificate.

#### Creating the Base64 Key from the `PKCS #12` Certificate

Use the following PowerShell script to create the base64-encoded key:

```powershell
$filePath = 'C:\Cert'
$pfxCertName = 'Cert.pfx'
$pfxPath = "$filePath\$pfxCertName"

$fileContentBytes = [System.IO.File]::ReadAllBytes("$pfxPath")
[System.Convert]::ToBase64String($fileContentBytes) | Set-Content "$filePath\HelloID_Cert_Base64.txt"
```

### Connection settings

The following settings are required to connect to the API.

| Setting              | Description                                                                    | Mandatory |
| -------------------- | ------------------------------------------------------------------------------ | --------- |
| P12CertificateBase64 | Base64-encoded PFX client certificate used for mTLS                            | Yes       |
| certificatePassword  | Password for the PFX client certificate                                        | Yes       |
| apiKey               | API key sent as a Bearer token                                                 | Yes       |
| BaseUrl              | Base URL of the Voskamp-VosForce API, Example: `https://101.<customerName>.nl` | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Voskamp-VosForce_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `employee_number`                 |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the `id` property from Voskamp-VosForce.

## Remarks

### Network access
- The API must be reachable from HelloID and support the required HTTPS connection.
- If Cloudflare is used in front of the API, verify that the route supports the required client certificate (mTLS).


### API permission errors
- The Get user call returns a 403 with a JSON error: `You don't have permission to access this.`. The connector treats the account as unavailable in this case.

### Voskamp-VosForce API limitations
The Voskamp-VosForce API is not aware of the current state of the Voskamp-VosForce application. HelloID can only retrieve the state stored in the API database, not the state directly from the application.

For this reason, HelloID can import accounts and permissions only from the VosForce API, not directly from the VosForce application.

For example, an employee may exist in the application but not in the API database. HelloID will then send a create request. The API checks whether the employee already exists using the employee number and, if so, correlates the request with the existing employee instead of creating a duplicate. The API then returns the existing employee as the correlated account.

The same behavior applies to permissions: existing permissions can be correlated through the API in the same way.

```mermaid
flowchart LR
    HELLOID["HelloID"] <--> API["API VosForce"]
    API --> APP["Application VosForce"]

    style HELLOID fill:#e0f2fe,stroke:#0284c7,stroke-width:2px
    style API fill:#fef3c7,stroke:#d97706,stroke-width:2px
    style APP fill:#dcfce7,stroke:#16a34a,stroke-width:2px
```

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                     | HTTP Method        | Description                                          |
| ---------------------------- | ------------------ | ---------------------------------------------------- |
| `/items/users`               | GET, POST          | Import, create, and correlate users                  |
| `/items/users/{id}`          | GET, PATCH, DELETE | Retrieve, enable, disable, update, and delete a user |
| `/items/roles`               | GET                | Retrieve roles used to name permissions              |
| `/items/authorizations`      | GET, POST          | Retrieve and grant user group authorizations         |
| `/items/authorizations/{id}` | DELETE             | Revoke a specific user group authorization           |

### API documentation

No public API documentation is available.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
