//! Valve's text key-value format, as used by `libraryfolders.vdf`, `appmanifest_*.acf`
//! and `localconfig.vdf`. Read only, and only what those files use.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub enum Vdf {
    Text(String),
    Map(BTreeMap<String, Vdf>),
}

impl Vdf {
    /// A child by name. Steam is not consistent about case ("apps" and "Apps" both occur).
    pub fn get(&self, key: &str) -> Option<&Vdf> {
        match self {
            Vdf::Map(m) => m.get(key).or_else(|| m.iter().find(|(k, _)| k.eq_ignore_ascii_case(key)).map(|(_, v)| v)),
            Vdf::Text(_) => None,
        }
    }

    pub fn path(&self, keys: &[&str]) -> Option<&Vdf> {
        keys.iter().try_fold(self, |at, key| at.get(key))
    }

    pub fn text(&self, key: &str) -> Option<&str> {
        match self.get(key) {
            Some(Vdf::Text(t)) => Some(t),
            _ => None,
        }
    }

    pub fn number(&self, key: &str) -> u64 {
        self.text(key).and_then(|t| t.parse().ok()).unwrap_or(0)
    }

    pub fn entries(&self) -> impl Iterator<Item = (&String, &Vdf)> {
        let map = match self {
            Vdf::Map(m) => Some(m),
            Vdf::Text(_) => None,
        };
        map.into_iter().flatten()
    }
}

/// Never fails: a damaged file gives what could be read up to the damage.
pub fn parse(text: &str) -> Vdf {
    let mut chars = text.chars().peekable();
    let mut stack: Vec<(Option<String>, BTreeMap<String, Vdf>)> = vec![(None, BTreeMap::new())];
    let mut key: Option<String> = None;
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                let mut word = String::new();
                while let Some(c) = chars.next() {
                    match c {
                        '"' => break,
                        '\\' => match chars.next() {
                            Some('n') => word.push('\n'),
                            Some('t') => word.push('\t'),
                            Some(other) => word.push(other),
                            None => break,
                        },
                        other => word.push(other),
                    }
                }
                match key.take() {
                    None => key = Some(word),
                    Some(k) => {
                        stack.last_mut().unwrap().1.insert(k, Vdf::Text(word));
                    }
                }
            }
            '{' => stack.push((key.take(), BTreeMap::new())),
            '}' if stack.len() > 1 => {
                let (name, map) = stack.pop().unwrap();
                stack.last_mut().unwrap().1.insert(name.unwrap_or_default(), Vdf::Map(map));
            }
            '/' if chars.peek() == Some(&'/') => {
                for c in chars.by_ref() {
                    if c == '\n' {
                        break;
                    }
                }
            }
            _ => {}
        }
    }
    // Unclosed sections (a file cut short) are kept.
    while stack.len() > 1 {
        let (name, map) = stack.pop().unwrap();
        stack.last_mut().unwrap().1.insert(name.unwrap_or_default(), Vdf::Map(map));
    }
    Vdf::Map(stack.pop().unwrap().1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_nested_sections_and_escapes() {
        let v = parse("\"AppState\"\n{\n\t\"appid\"\t\t\"20920\"\n\t\"name\"\t\t\"The \\\"Witcher\\\" 2\"\n\t\"UserConfig\"\n\t{\n\t\t\"BetaKey\"\t\t\"public\"\n\t}\n}\n");
        let app = v.get("AppState").unwrap();
        assert_eq!(app.number("appid"), 20920);
        assert_eq!(app.text("name"), Some("The \"Witcher\" 2"));
        assert_eq!(v.path(&["AppState", "UserConfig"]).unwrap().text("BetaKey"), Some("public"));
    }

    #[test]
    fn keys_are_found_whatever_their_case() {
        let v = parse("\"Software\" { \"Valve\" { \"Steam\" { \"Apps\" { \"10\" { \"Playtime\" \"7\" } } } } }");
        assert_eq!(v.path(&["software", "valve", "steam", "apps", "10"]).unwrap().number("playtime"), 7);
    }

    #[test]
    fn a_file_cut_short_gives_what_was_read() {
        let v = parse("\"libraryfolders\" { \"0\" { \"path\" \"/a\" \"apps\" { \"10\" \"5");
        assert_eq!(v.path(&["libraryfolders", "0"]).unwrap().text("path"), Some("/a"));
    }
}
