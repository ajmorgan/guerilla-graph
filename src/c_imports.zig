//! Centralized C imports for Guerilla Graph.
//!
//! This module provides a single @cImport of sqlite3.h to ensure
//! type compatibility across all modules. Each module's separate
//! @cImport creates distinct, incompatible types, causing issues
//! with pointer passing between modules.

pub const c = @cImport(@cInclude("sqlite3.h"));
