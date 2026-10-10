# Shared Jinja fragments: keep manual arbitration and motion eligibility equal.
{ policy }:
let
  z = policy.motionZones.bathroom;
  a = z.ambient;
  lamp = builtins.head z.lights;
  prelude = "{% set ambient = states('${a.helper}')[8:] | from_json({}) %}";
  # An unchanged numeric reading is not a missing sensor. A last-reported low
  # value establishes darkness even if the lamp is already on; do not relabel it
  # as a fresh measurement. Owned cycles ignore lamp-generated high lux. Only
  # inferring darkness through a HIGH lamp-on reading needs a recent OFF sample.
  valid = ''
    (is_number(states('${z.illuminance}')) and 0 <= states('${z.illuminance}') | float <= 100000
     and not states.${z.illuminance}.attributes.get('restored', false)
     and (is_state('${z.active}', 'on')
          or states('${z.illuminance}') | float < ${toString z.darkLux}
          or (not is_state('${lamp}', 'off')
              and ambient is mapping
              and is_number(ambient.get('lux')) and 0 <= ambient.get('lux') | float < ${toString z.darkLux}
              and is_number(ambient.get('sampled'))
              and 0 <= as_timestamp(now()) - (ambient.get('sampled') | float) <= ${toString a.maxAgeSeconds})))
  '';
  # Local wall-clock schedule is independent of every illuminance value.
  percent = "(${toString z.brightnessSchedule.nightBrightnessPct} if now().strftime('%H:%M:%S') < '${z.brightnessSchedule.nightUntil}' else ${toString z.brightnessSchedule.dayBrightnessPct})";
in {
  inherit prelude valid percent;
  # Invalidate nothing on a transient manual OFF: occupied automatic ownership
  # still wins using its latched sample. A new valid OFF sample replaces it.
  captureSequence = [
    { condition = "state"; entity_id = lamp; state = "off"; }
    { condition = "template"; value_template = ''
        ${prelude}
        {% set source = states.${z.illuminance} %}
        {% set light = states.${lamp} %}
        {{ source is not none and light is not none
           and not source.attributes.get('restored', false)
           and not light.attributes.get('restored', false)
           and is_number(source.state) and 0 <= source.state | float <= 100000
           and ambient is mapping and is_number(ambient.get('started'))
           and as_timestamp(source.last_reported) > ambient.get('started') | float
           and as_timestamp(source.last_reported) >= as_timestamp(light.last_changed) + ${toString a.settleSeconds}
           and 0 <= as_timestamp(now()) - as_timestamp(source.last_reported) <= ${toString a.maxAgeSeconds} }}
      ''; }
    { variables.sample = ''
        ${prelude}
        {{ {'lux': states('${z.illuminance}') | float,
            'sampled': as_timestamp(states.${z.illuminance}.last_reported),
            'started': ambient.get('started')} }}
      ''; }
    { condition = "template"; value_template = "{{ states('${a.helper}')[8:] | from_json({}) != sample }}"; }
    { action = "input_text.set_value"; target.entity_id = a.helper;
      # Prefix prevents HA's native template rendering from converting JSON
      # back into a dict before the input_text string service validation.
      data.value = "ambient:{{ sample | to_json }}"; }
  ];
}
