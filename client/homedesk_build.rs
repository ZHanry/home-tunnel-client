// HOMEDESK: Isolated build-time reader for the monorepo brand configuration.
use std::{collections::HashMap, env, fs, path::PathBuf};

#[derive(Debug, PartialEq)]
struct BrandConfig {
    app_name: String,
    executable_name: String,
    package_name: String,
}

pub fn configure() {
    if let Err(error) = configure_inner() {
        panic!("HomeDesk brand configuration failed: {}", error);
    }
}

fn configure_inner() -> Result<(), String> {
    println!("cargo:rerun-if-env-changed=HOMEDESK_CONFIG_PATH");
    let source = resolve_config_path()?;
    println!("cargo:rerun-if-changed={}", source.display());
    let content = fs::read_to_string(&source)
        .map_err(|error| format!("cannot read {}: {error}", source.display()))?;
    let config = parse_brand(&content)?;

    println!("cargo:rustc-env=HOMEDESK_APP_NAME={}", config.app_name);
    println!(
        "cargo:rustc-env=HOMEDESK_EXECUTABLE_NAME={}",
        config.executable_name
    );
    println!(
        "cargo:rustc-env=HOMEDESK_PACKAGE_NAME={}",
        config.package_name
    );
    Ok(())
}

fn resolve_config_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("HOMEDESK_CONFIG_PATH") {
        return Ok(PathBuf::from(path));
    }
    let manifest_dir = env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .ok_or_else(|| "CARGO_MANIFEST_DIR is not set".to_owned())?;
    let root = manifest_dir
        .parent()
        .ok_or_else(|| format!("{} has no parent directory", manifest_dir.display()))?;
    let local = root.join("build/config.toml");
    if local.is_file() {
        return Ok(local);
    }
    Ok(root.join("build/config.toml.example"))
}

fn parse_brand(content: &str) -> Result<BrandConfig, String> {
    let mut section = "";
    let mut values = HashMap::new();
    for (index, raw_line) in content.lines().enumerate() {
        let line = strip_comment(raw_line).trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            section = line[1..line.len() - 1].trim();
            continue;
        }
        if section != "brand" {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            return Err(format!("line {} is not a key/value pair", index + 1));
        };
        let key = key.trim();
        let value = parse_basic_string(value.trim())
            .map_err(|error| format!("line {}: {error}", index + 1))?;
        if values.insert(key.to_owned(), value).is_some() {
            return Err(format!("line {} repeats brand.{key}", index + 1));
        }
    }

    let config = BrandConfig {
        app_name: required(&values, "app_name")?,
        executable_name: required(&values, "executable_name")?,
        package_name: required(&values, "package_name")?,
    };
    validate(&config)?;
    Ok(config)
}

fn strip_comment(line: &str) -> &str {
    let mut quoted = false;
    let mut escaped = false;
    for (index, character) in line.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if quoted && character == '\\' {
            escaped = true;
        } else if character == '"' {
            quoted = !quoted;
        } else if character == '#' && !quoted {
            return &line[..index];
        }
    }
    line
}

fn parse_basic_string(value: &str) -> Result<String, String> {
    if value.len() < 2 || !value.starts_with('"') || !value.ends_with('"') {
        return Err("brand values must be double-quoted strings".to_owned());
    }
    let mut decoded = String::new();
    let mut characters = value[1..value.len() - 1].chars();
    while let Some(character) = characters.next() {
        if character != '\\' {
            decoded.push(character);
            continue;
        }
        let Some(escaped) = characters.next() else {
            return Err("brand string ends with an incomplete escape".to_owned());
        };
        decoded.push(match escaped {
            '"' => '"',
            '\\' => '\\',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            _ => return Err(format!("unsupported escape: \\{escaped}")),
        });
    }
    Ok(decoded)
}

fn required(values: &HashMap<String, String>, key: &str) -> Result<String, String> {
    values
        .get(key)
        .cloned()
        .ok_or_else(|| format!("missing brand.{key}"))
}

fn validate(config: &BrandConfig) -> Result<(), String> {
    if config.app_name.is_empty() || config.app_name.chars().count() > 64 {
        return Err("brand.app_name must contain 1 to 64 characters".to_owned());
    }
    if config.app_name.chars().any(char::is_control) {
        return Err("brand.app_name cannot contain control characters".to_owned());
    }
    if config.app_name.trim() != config.app_name
        || config
            .app_name
            .chars()
            .any(|character| r#"<>:"/\|?*"#.contains(character))
    {
        return Err(
            "brand.app_name cannot contain reserved filename characters or surrounding spaces"
                .to_owned(),
        );
    }
    for (key, value) in [
        ("executable_name", config.executable_name.as_str()),
        ("package_name", config.package_name.as_str()),
    ] {
        let valid = value.chars().enumerate().all(|(index, character)| {
            character.is_ascii_lowercase()
                || (index > 0 && (character.is_ascii_digit() || character == '-'))
        }) && !value.ends_with('-');
        if value.is_empty() || value.len() > 64 || !valid {
            return Err(format!("brand.{key} must be a lowercase kebab-case name"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_brand_section_without_reading_other_secrets() {
        let config = parse_brand(
            r#"
                [brand]
                app_name = "HomeDesk"
                executable_name = "homedesk"
                package_name = "homedesk"

                [server]
                key = "not-read"
            "#,
        );
        assert_eq!(
            Ok(BrandConfig {
                app_name: "HomeDesk".to_owned(),
                executable_name: "homedesk".to_owned(),
                package_name: "homedesk".to_owned(),
            }),
            config
        );
    }

    #[test]
    fn rejects_unsafe_executable_name() {
        let error = parse_brand(
            r#"
                [brand]
                app_name = "HomeDesk"
                executable_name = "../../home"
                package_name = "homedesk"
            "#,
        );
        assert!(error.is_err());
    }
}
