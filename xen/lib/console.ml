(*
 * Copyright (c) 2010 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Lwt
open Printf

type t = {
  backend_id: int;
  gnt: Gnttab.grant_table_index;
  ring: Cstruct.t;
  evtchn: Eventchn.t;
  waiters: unit Lwt.u Lwt_sequence.t;
}

exception Internal_error of string

(** Called by a console thread that wishes to sleep (or be cancelled) *)
let wait cons =
  Activations.wait cons.evtchn

external console_start_page: unit -> Io_page.t = "caml_console_start_page"

let h = Eventchn.init ()

let create () =
  let backend_id = 0 in
  let gnt = Gnttab.console in
  let page = console_start_page () in
  let ring = Io_page.to_cstruct page in
  Console_ring.Ring.init ring; (* explicitly zero the ring *)
  let evtchn = Eventchn.console_port () in
  let waiters = Lwt_sequence.create () in
  let con = { backend_id; gnt; ring; evtchn; waiters } in
  ignore(Eventchn.unmask h evtchn);
  ignore(Eventchn.notify h evtchn);
  con
    
let rec sync_write cons buf off len =
  assert(len <= String.length buf + off);
  let w = Console_ring.Ring.Front.unsafe_write cons.ring buf off len in
  ignore(Eventchn.notify h cons.evtchn);
  let left = len - w in
  if left = 0 then 
    return () 
  else (
    wait cons >>
    sync_write cons buf (off+w) left
  )

let write cons buf off len =
  assert(len <= String.length buf + off);
  let _ = Console_ring.Ring.Front.unsafe_write cons.ring buf off len in
  ignore(Eventchn.notify h cons.evtchn)

let t = create ()

let log s = 
  let s = s ^ "\r\n" in
  write t s 0 (String.length s)

let log_s s =
  let s = s ^ "\r\n" in
  sync_write t s 0 (String.length s)
