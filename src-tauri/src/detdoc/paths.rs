use globset::{Glob, GlobSetBuilder};

use super::config::DetDocConfig;

pub fn is_denied_path(path: &str, config: &DetDocConfig) -> bool {
    matches_any(path, &config.paths.deny)
}

pub fn is_doc_path(path: &str, config: &DetDocConfig) -> bool {
    matches_any(path, &config.docs.include) && !matches_any(path, &config.docs.exclude)
}

fn matches_any(path: &str, patterns: &[String]) -> bool {
    let mut builder = GlobSetBuilder::new();
    for pattern in patterns {
        if let Ok(glob) = Glob::new(pattern) {
            builder.add(glob);
        }
    }
    builder.build().map(|set| set.is_match(path)).unwrap_or(false)
}
