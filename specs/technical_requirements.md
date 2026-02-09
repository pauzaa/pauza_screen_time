# Technical Requirements

This document outlines the architectural principles and technical requirements for the project. These guidelines must be strictly followed during development.

## 1. Strong Typization

### Requirement
All data structures, errors, and models must be strongly typed. 

### Guidelines
- **Models**: Use clearly defined classes or structs for all data models. Avoid using generic types like `Map<String, dynamic>`, `Dictionary`, or `Object` where a specific type can be defined.
- **Aggregation**: logical models should be aggregated into meaningful structures.
- **Cross-Platform Consistency**: Type safety must be enforced on both the Dart side (Flutter) and the Native platforms (Android/Kotlin, iOS/Swift).
  - **Dart**: Use strict types.
  - **Kotlin/Swift**: Use data classes/structs to ensure type safety for method channels and internal logic.

## 2. Honest Fast-Failure

### Requirement
Errors must not be silently ignored or swallowed. The system should fail fast and loudly with a typed error when an exception occurs.

### Guidelines
- **Typed Errors**: Define specific error classes for different failure scenarios (e.g., `PermissionsDeniedError`, `ServiceUnavailableError`).
- **No Silencing**: Do not use empty `catch` blocks. If an exception is caught, it must be wrapped in a meaningful typed error and rethrown or returned.
- **Propagation**: Errors occurring in native code must be serialized and sent to Dart as typed errors, ensuring the UI or logic layer can handle them appropriately.

## 3. No God Class

### Requirement
Avoid creating single classes that handle too many responsibilities. Adhere to the Single Responsibility Principle (SRP).

### Guidelines
- **Decomposition**: Break down functionality into smaller, logical modules.
  - Use **Repositories** for data access.
  - Use **Handlers** for specific platform logic.
  - Use **Services** for business logic.
- **Logical Division**: Ensure that each class has a clear, focused purpose. If a class grows too large, refactor it into smaller components.
- **Native & Dart**: This principle applies equally to both Dart code and platform-specific native code.

## 4. Documented

### Requirement
All code, assumptions, and limitations must be clearly documented.

### Guidelines
- **Beginner-Friendly**: Documentation should be easy to understand for developers of all skill levels.
- **Detailed Steps**: Complex logic or workflows should be explained with step-by-step comments or external documentation.
- **Assumptions & Limitations**: Explicitly document any assumptions made during implementation and any known limitations of the solution.
- **API Documentation**: Public methods and classes should have clear doc comments explaining their purpose, parameters, and return values.
