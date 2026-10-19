extends RefCounted
class_name SoundIds

## Ids de TODOS los eventos de sonido del juego. Usarlos así:  Audio.play(SoundIds.PLAYER_JUMP)
##
## Cada constante corresponde a un archivo Resources/audio/events/<categoria>/<id>.tres. Usar la constante
## (y no un string suelto) hace que un error de tipeo falle al escribir el código en vez de quedar mudo.
## Para sumar un sonido: crear su .tres y agregar acá su constante (ver Docs/sistema_de_audio.md).

# ---------------------------------------------------------------- JUGADOR
const PLAYER_FOOTSTEP: StringName = &"player_footstep"
const PLAYER_JUMP: StringName = &"player_jump"
const PLAYER_DOUBLE_JUMP: StringName = &"player_double_jump"
const PLAYER_LAND: StringName = &"player_land"
const PLAYER_GUITAR_SWING: StringName = &"player_guitar_swing"
const PLAYER_GUITAR_HIT: StringName = &"player_guitar_hit"
const PLAYER_DAMAGE: StringName = &"player_damage"
const PLAYER_RIFLE_ENTER: StringName = &"player_rifle_enter"
const PLAYER_RIFLE_EXIT: StringName = &"player_rifle_exit"
const PLAYER_RIFLE_SHOOT: StringName = &"player_rifle_shoot"

# ---------------------------------------------------------------- ENEMIGOS
const ENEMY_SPAWN: StringName = &"enemy_spawn"
const ENEMY_ALERT: StringName = &"enemy_alert"
const ENEMY_FOOTSTEP: StringName = &"enemy_footstep"
const ENEMY_IDLE: StringName = &"enemy_idle"
const ENEMY_ATTACK_WINDUP: StringName = &"enemy_attack_windup"
const ENEMY_ATTACK_HIT: StringName = &"enemy_attack_hit"
const ENEMY_STRIKE_OBJECT: StringName = &"enemy_strike_object"
const ENEMY_HURT: StringName = &"enemy_hurt"
const ENEMY_DIE: StringName = &"enemy_die"

# ---------------------------------------------------------------- FAROLITOS
const FAROLITO_HIT: StringName = &"farolito_hit"
const FAROLITO_FLICKER: StringName = &"farolito_flicker"
const FAROLITO_ON: StringName = &"farolito_on"
const FAROLITO_OFF: StringName = &"farolito_off"
const FAROLITO_BUZZ_LOOP: StringName = &"farolito_buzz_loop"

# ---------------------------------------------------------------- RADIO
const RADIO_INSERT_TAPE: StringName = &"radio_insert_tape"
const RADIO_PLAY_START: StringName = &"radio_play_start"
const RADIO_EJECT: StringName = &"radio_eject"
const RADIO_HIT: StringName = &"radio_hit"
const RADIO_TAPE_END: StringName = &"radio_tape_end"
const RADIO_STATIC_LOOP: StringName = &"radio_static_loop"

# ---------------------------------------------------------------- CASSETTES
const CASSETTE_PICKUP: StringName = &"cassette_pickup"
const CASSETTE_DROP: StringName = &"cassette_drop"
const CASSETTE_REWIND: StringName = &"cassette_rewind"

# ---------------------------------------------------------------- OBJETOS INTERACTUABLES
const OBJECT_INSPECT_OPEN: StringName = &"object_inspect_open"
const OBJECT_INSPECT_CLOSE: StringName = &"object_inspect_close"
const OBJECT_PICTURE_OPEN: StringName = &"object_picture_open"
const OBJECT_PICTURE_CLOSE: StringName = &"object_picture_close"

# ---------------------------------------------------------------- PUERTAS Y ALCANTARILLA
const DOOR_OPEN: StringName = &"door_open"
const DOOR_CLOSE: StringName = &"door_close"
const DOOR_SEWER_OPEN: StringName = &"door_sewer_open"
const DOOR_SEWER_CLOSE: StringName = &"door_sewer_close"

# ---------------------------------------------------------------- PUZZLE
const PUZZLE_SOLVED: StringName = &"puzzle_solved"
const PUZZLE_UNSOLVED: StringName = &"puzzle_unsolved"

# ---------------------------------------------------------------- NIVEL (progreso y final)
const LEVEL_WARP: StringName = &"level_warp"
const LEVEL_PROGRESS_START: StringName = &"level_progress_start"
const LEVEL_PROGRESS_PAUSE: StringName = &"level_progress_pause"
const LEVEL_PROGRESS_COMPLETE: StringName = &"level_progress_complete"
const LEVEL_ENDING_MESSAGE: StringName = &"level_ending_message"

# ---------------------------------------------------------------- INTERFAZ Y MENÚS
const UI_MENU_MOVE: StringName = &"ui_menu_move"
const UI_MENU_CONFIRM: StringName = &"ui_menu_confirm"
const UI_MENU_CANCEL: StringName = &"ui_menu_cancel"
const UI_MENU_ERROR: StringName = &"ui_menu_error"
const UI_SLIDER_TICK: StringName = &"ui_slider_tick"
const UI_TOGGLE: StringName = &"ui_toggle"
const UI_INVENTORY_OPEN: StringName = &"ui_inventory_open"
const UI_INVENTORY_CLOSE: StringName = &"ui_inventory_close"
const UI_PAUSE_OPEN: StringName = &"ui_pause_open"
const UI_PAUSE_CLOSE: StringName = &"ui_pause_close"
const UI_GAME_START: StringName = &"ui_game_start"

# ---------------------------------------------------------------- AMBIENTES (loops)
const AMB_RAIN_LOOP: StringName = &"amb_rain_loop"

# ---------------------------------------------------------------- MÚSICA
const MUS_MENU_THEME: StringName = &"mus_menu_theme"
