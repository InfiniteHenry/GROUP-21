export type Rating = 0 | 1;
export type CardOrder = 'saved' | 'shuffle';
export type QueueMode = 'due' | 'manual' | 'shuffle';
export interface Deck { id:string; name:string; emoji:string; color:string; description:string; position:number; card_order:CardOrder; created_at:string; updated_at:string; }
export interface Card { id:string; deck_id:string; front:string; back:string; position:number; created_at:string; updated_at:string; }
export interface CardState { card_id:string; due_at:string; interval_days:number; correct_streak:number; reps:number; lapses:number; last_reviewed_at:string|null; }
export interface Review { id:string; card_id:string; session_id:string; rating:Rating; reviewed_at:string; }
export interface StudySession { id:string; deck_id:string|null; mode:QueueMode; started_at:string; finished_at:string|null; card_ids:string[]; answers:number; correct:number; }
export interface Profile { display_name:string; timezone:string; daily_goal:number; guest:boolean; }
export interface Dashboard { due_now:number; reviews_today:number; accuracy_7d:number|null; streak:{current:number;longest:number}; decks:Array<{id:string;name:string;emoji:string;color:string;card_count:number;due_count:number;mastery:number}>; }
export interface StatsHistory { days:Array<{date:string;reviews:number;correct:number}>; accuracy:number|null; total_reviews:number; streak:{current:number;longest:number}; }
export interface SyncStatus { state:'guest'|'idle'|'syncing'|'offline'|'auth_required'|'error'; pending:number; lastSyncedAt:string|null; error:string|null; nextRetryAt:string|null; }
export interface RecallAPIInstance {
 ready():Promise<this>; on(event:'change'|'status'|'auth'|'rejected',cb:(payload:any)=>void):()=>void;
 auth:{session():{user:{id:string;email:string|null;name:string|null;avatarUrl:string|null}}|null;signInWithGoogle():Promise<void>;signOut(options?:{force?:boolean}):Promise<void>};
 decks:{list():Promise<Deck[]>;get(id:string):Promise<Deck>;create(input:{name:string;emoji?:string;color?:string;description?:string;card_order?:CardOrder}):Promise<Deck>;update(id:string,input:{name?:string;emoji?:string;color?:string;description?:string;card_order?:CardOrder}):Promise<Deck>;remove(id:string):Promise<void>;reorder(ids:string[]):Promise<void>};
 cards:{list(deckId:string):Promise<Array<Card&{state:CardState|null}>>;get(id:string):Promise<Card>;create(deckId:string,input:{front:string;back:string}):Promise<Card&{state:CardState}>;update(id:string,input:{front?:string;back?:string;deck_id?:string}):Promise<Card>;remove(id:string):Promise<void>;reorder(deckId:string,ids:string[]):Promise<void>};
 study:{queue(input?:{deckId?:string;mode?:QueueMode;limit?:number}):Promise<Array<{card:Card;state:CardState|null}>>;start(input?:{deckId?:string;mode?:QueueMode}):Promise<StudySession>;answer(sessionId:string,cardId:string,rating:Rating):Promise<{state:CardState;review:Review;session:StudySession}>;finish(sessionId:string):Promise<StudySession>};
 stats:{dashboard():Promise<Dashboard>;history(days:number):Promise<StatsHistory>;serverHistory(days:number):Promise<StatsHistory>};
 profile:{get():Promise<Profile>;update(input:{display_name?:string;timezone?:string;daily_goal?:number}):Promise<Profile>};
 sync:{now():Promise<SyncStatus>;status():SyncStatus}; account:{delete():Promise<{deleted:true}>;export(format:'json'|'csv'):Promise<object|string>};
 importData(snapshot:unknown):Promise<{imported:number;skipped:number}>; destroy():void;
}
export declare class RecallError extends Error { code:'invalid_input'|'not_found'|'not_ready'|'auth_required'|'unsynced_changes'|'offline'|'rate_limited'|'forbidden'|'server_error'|'storage_unavailable'|'storage_error'|'config_error'; problems?:string[]; count?:number; }
export declare const contract:{CONTRACT_VERSION:number;LIMITS:Readonly<Record<string,number>>};
export declare function createRecallAPI(options:{backend:'mock'}|{backend:'supabase';supabase:any}):RecallAPIInstance;
declare const RecallAPI:{createRecallAPI:typeof createRecallAPI;contract:typeof contract;RecallError:typeof RecallError};
export default RecallAPI;
