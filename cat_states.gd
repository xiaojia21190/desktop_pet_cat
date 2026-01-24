class_name CatStates
extends RefCounted

## 猫咪状态名称常量
## 集中管理所有状态名称，避免字符串硬编码

const IDLE := &"Idle"
const WALKING := &"Walking"
const WATCHING := &"Watching"
const POUNCING := &"Pouncing"
const CHASING := &"Chasing"
const BLOCKING := &"Blocking"
const ROLLING := &"Rolling"
const TAIL_WAGGING := &"TailWagging"
const IGNORING := &"Ignoring"
const TYPING_ATTACK := &"TypingAttack"
const EATING := &"Eating"
const CARRYING := &"Carrying"
