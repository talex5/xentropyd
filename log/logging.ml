(*
 * Copyright (C) Citrix Systems Inc.
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
open Sexplib

type logger = {
  stream: string Lwt_stream.t;
  push: string -> unit;
  elements: int ref;
  max_elements: int;
  dropped_elements: int ref;
  mutable shutdown: bool;
}

let create max_elements =
  let elements = ref (ref 0) in
  let dropped_elements = ref (ref 0) in
  let stream, stream_push = Lwt_stream.create () in
  let push line =
    if !(!elements) > max_elements then begin
      incr !dropped_elements
    end else begin
      stream_push (Some line);
      incr !elements
    end in
  {
    stream = stream;
    push = push;
    elements = !elements;
    max_elements = max_elements;
    dropped_elements = !dropped_elements;
    shutdown = false;
  }

let get (logger: logger) =
  let return_lines all =
    logger.elements := !(logger.elements) - (List.length all);
    let dropped = !(logger.dropped_elements) in
    logger.dropped_elements := 0;
    return (if dropped <> 0
            then Printf.sprintf "<-- dropped %d log lines" dropped :: all
            else all) in

  (* Grab as many elements as we can without blocking *)
  let all = Lwt_stream.get_available logger.stream in
  if all <> [] || logger.shutdown
  then return_lines all
  else begin
    (* Block for at least one line *)
    Lwt_stream.nget 1 logger.stream >>= fun all ->
    return_lines all
  end

let shutdown logger = logger.shutdown <- true

(* General system logging *)
let logger = create 512

type level = Debug | Info | Warn | Error | Null

let log_level = ref Warn

let string_of_level = function
  | Debug -> "debug" | Info -> "info" | Warn -> "warn"
  | Error -> "error" | Null -> "null"

let log level key (fmt: (_,_,_,_) format4) =
  let level = string_of_level level in
  Printf.ksprintf logger.push ("[%5s|%s] " ^^ fmt) level key

let debug key = log Debug key
let info key = log Info key
let warn key = log Warn key
let error key = log Error key
