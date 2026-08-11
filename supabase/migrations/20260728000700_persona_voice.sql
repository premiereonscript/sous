-- Sous — generic voice archetypes + free-text voice customization.
--
-- The default persona was named after a real person ("weissman"), both as the
-- stored value and in the prompt that described the voice. That is a poor thing
-- to ship in a public repo: it attaches a living person's name and manner to a
-- synthetic character nobody asked them about. The voice itself is unchanged in
-- character — high-energy, opinionated, dry — it is just described as an
-- archetype now rather than as an impression of someone.
--
-- 'weissman' -> 'bold'. Existing households keep the voice they had.

alter table household_preferences alter column persona_style set default 'bold';

update household_preferences
   set persona_style = 'bold'
 where persona_style = 'weissman';

-- Free-text steering in the household's own words, folded into whichever style
-- they picked ("talk like a grumpy French chef", "keep it to one line").
-- Bounded in code (PERSONA_NOTE_MAX) so it can't crowd out the household
-- context or the dietary rules that follow it in the system prompt.
alter table household_preferences
  add column if not exists persona_note text;

-- Only the three archetypes are valid; anything else would silently fall back
-- to the default in personaVoice() with no signal that it had.
alter table household_preferences
  drop constraint if exists household_preferences_persona_style_check;
alter table household_preferences
  add constraint household_preferences_persona_style_check
  check (persona_style in ('bold', 'neutral', 'warm'));
