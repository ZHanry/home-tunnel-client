// Desktop and bundled Agent releases can advance independently. The approved
// combination is embedded at build time, rather than supplied by the runtime.
use serde_json::Value;

pub fn validate(manifest: &Value, executable: &str) -> Result<(), &'static str> {
    let compatibility: Value = serde_json::from_str(include_str!("../../compatibility.json"))
        .map_err(|_| "RUNTIME_INCOMPATIBLE")?;
    let client_version = env!("CARGO_PKG_VERSION");
    let expected_runtime = compatibility["target_combination"]["agent"]
        .as_str().filter(|version| !version.is_empty()).ok_or("RUNTIME_INCOMPATIBLE")?;
    if compatibility["version"].as_str() != Some(client_version)
        || compatibility["target_combination"]["client"].as_str() != Some(client_version)
        || manifest["version"].as_str() != Some(expected_runtime)
    {
        return Err("RUNTIME_INCOMPATIBLE");
    }
    if manifest["parent_executable"].as_str() != Some(executable) {
        return Err("INTEGRITY_FAILED");
    }
    Ok(())
}
