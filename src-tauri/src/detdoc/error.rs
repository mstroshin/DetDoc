use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetDocError {
    code: String,
    message: String,
}

pub type DetDocResult<T> = Result<T, DetDocError>;

impl DetDocError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn code(&self) -> &str {
        &self.code
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

impl Display for DetDocError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for DetDocError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display_includes_code_and_message() {
        let error = DetDocError::new("CONFIG_MISSING", "DetDoc config is missing");
        assert_eq!(error.code(), "CONFIG_MISSING");
        assert_eq!(error.to_string(), "CONFIG_MISSING: DetDoc config is missing");
    }
}
