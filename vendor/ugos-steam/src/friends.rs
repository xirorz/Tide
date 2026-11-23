//! The signed-in player and their Steam friends, read from the client's friends list.
//!
//! Where Steam keeps them is not a public interface. [`fields`] names every place this
//! reads, each with the names to try in order; when a Steam update moves one, correct it
//! there. `ugos-steam friends --check` says which names were found and how many friends
//! had each field, and never prints a name, an id or a picture id.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// Where the friends list is, as paths from the page's globals (`store`), from the store
/// (`list`, `me`) and from one person (the rest). A person's fields are looked up on its
/// `persona` when it has one, else on the person itself.
pub fn fields() -> Value {
    json!({
        "store": ["g_FriendsUIApp.FriendStore", "friendStore"],
        "list": ["all_friends", "allFriends"],
        "me": ["self", "m_self"],
        "persona": ["persona", "m_persona"],
        "name": ["m_strPlayerName", "display_name"],
        "avatar": ["m_strAvatarHash"],
        "state": ["m_ePersonaState"],
        "appid": ["m_unGamePlayedAppID"],
        "game": ["m_strGameExtraInfo"]
    })
}

/// One person as the script hands them over.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct RawPerson {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub avatar: Option<String>,
    #[serde(default)]
    pub state: Option<i64>,
    #[serde(default)]
    pub appid: Option<u64>,
    #[serde(default)]
    pub game: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RawFriends {
    #[serde(default)]
    pub me: Option<RawPerson>,
    #[serde(default)]
    pub friends: Vec<RawPerson>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Presence {
    InGame,
    Online,
    Away,
    Offline,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Person {
    pub name: String,
    /// The picture's id on Steam's picture server (40 hex digits), when known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar: Option<String>,
    pub presence: Presence,
    /// The game being played: its Steam app id (0 for a game Steam does not sell), its name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub appid: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Friends {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub me: Option<Person>,
    pub playing: usize,
    pub online: usize,
    /// In a game first, then online, then away or busy, then offline; by name within each.
    pub friends: Vec<Person>,
}

/// Steam's persona states: 0 offline, 1 online, 2 busy, 3 away, 4 snooze, 5 looking to
/// trade, 6 looking to play. Someone in a game is in a game whatever the state says.
fn presence(p: &RawPerson) -> Presence {
    let playing = p.appid.is_some_and(|a| a > 0) || p.game.as_deref().is_some_and(|g| !g.trim().is_empty());
    match p.state.unwrap_or(0) {
        s if s <= 0 => Presence::Offline,
        _ if playing => Presence::InGame,
        1 | 5 | 6 => Presence::Online,
        _ => Presence::Away,
    }
}

fn avatar(hash: Option<&str>) -> Option<String> {
    let hash = hash?.trim().to_ascii_lowercase();
    (hash.len() == 40 && hash.bytes().all(|b| b.is_ascii_hexdigit()) && hash.bytes().any(|b| b != b'0')).then_some(hash)
}

fn person(p: &RawPerson) -> Option<Person> {
    let name = p.name.as_deref().map(str::trim).filter(|n| !n.is_empty())?.to_string();
    let presence = presence(p);
    let in_game = presence == Presence::InGame;
    Some(Person {
        name,
        avatar: avatar(p.avatar.as_deref()),
        presence,
        appid: p.appid.filter(|_| in_game),
        game: p.game.as_deref().map(str::trim).filter(|g| in_game && !g.is_empty()).map(String::from),
    })
}

pub fn shape(raw: &RawFriends) -> Friends {
    let mut friends: Vec<Person> = raw.friends.iter().filter_map(person).collect();
    friends.sort_by(|a, b| a.presence.cmp(&b.presence).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    Friends {
        me: raw.me.as_ref().and_then(person),
        playing: friends.iter().filter(|f| f.presence == Presence::InGame).count(),
        online: friends.iter().filter(|f| f.presence != Presence::Offline).count(),
        friends,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(name: &str, state: i64, appid: u64, game: &str) -> RawPerson {
        RawPerson { name: Some(name.into()), avatar: Some("ab".repeat(20)), state: Some(state), appid: Some(appid), game: Some(game.into()) }
    }

    #[test]
    fn in_game_then_online_then_away_then_offline() {
        let f = shape(&RawFriends {
            me: Some(raw("Me", 1, 0, "")),
            friends: vec![raw("zed", 0, 0, ""), raw("Amy", 3, 0, ""), raw("bob", 1, 0, ""), raw("Cy", 1, 570, "Dota 2"), raw("al", 1, 0, ""), raw("Dee", 2, 0, "")],
        });
        let order: Vec<_> = f.friends.iter().map(|p| (p.name.as_str(), p.presence)).collect();
        assert_eq!(
            order,
            [("Cy", Presence::InGame), ("al", Presence::Online), ("bob", Presence::Online), ("Amy", Presence::Away), ("Dee", Presence::Away), ("zed", Presence::Offline)]
        );
        assert_eq!((f.playing, f.online), (1, 5));
        assert_eq!(f.friends[0].appid, Some(570));
        assert_eq!(f.me.unwrap().presence, Presence::Online);
    }

    #[test]
    fn a_game_steam_does_not_sell_still_counts_as_playing() {
        let p = person(&raw("x", 1, 0, "Some Emulator")).unwrap();
        assert_eq!((p.presence, p.appid, p.game.as_deref()), (Presence::InGame, Some(0), Some("Some Emulator")));
    }

    #[test]
    fn offline_with_a_stale_game_is_offline_and_has_no_game() {
        let p = person(&raw("x", 0, 570, "Dota 2")).unwrap();
        assert_eq!((p.presence, p.appid, p.game), (Presence::Offline, None, None));
    }

    #[test]
    fn only_a_real_picture_id_is_kept() {
        assert_eq!(avatar(Some(&"AB".repeat(20))), Some("ab".repeat(20)));
        assert_eq!(avatar(Some("0000000000000000000000000000000000000000")), None);
        assert_eq!(avatar(Some("https://x/y.jpg")), None);
        assert_eq!(avatar(None), None);
    }

    #[test]
    fn nameless_people_are_left_out() {
        let f = shape(&RawFriends { me: None, friends: vec![RawPerson { state: Some(1), ..Default::default() }, raw("a", 1, 0, "")] });
        assert_eq!(f.friends.len(), 1);
    }
}
