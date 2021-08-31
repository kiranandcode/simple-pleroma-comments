(**
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*)
open Core_kernel
open Js_of_ocaml
open Js_of_ocaml_tyxml
open Cohttp_lwt_xhr
module T = Tyxml_js

(** your home pleroma instance - this is the instance where you post your comments from *)
let instance_url = "https://mastadon.social.com"

(** tag specifying DOM element with comment id *)
let base_comment_id = "comments"

(** url for reply-to icon *)
let reply_icon_url = "https://upload.wikimedia.org/wikipedia/commons/9/95/Ic_reply_48px.svg"

(** converts a ActivityPub Account into a HTML representation *)
let account_to_html_opt (acct: Yojson.Basic.t) =
  let open Yojson.Basic.Util in
  let (let+) x f = Option.bind x ~f in
  let+ avatar =
    member "avatar" acct
    |> to_string_option |> Option.first_some (member "avatar_static" acct |> to_string_option) in
  let+ display_name = member "display_name" acct |> to_string_option in
  let url =
    let url = member "url" acct |> to_string_option in
    match url with
    | None -> []
    | Some url -> T.Html.[a_href url]
  in
  Option.return @@ T.Html.(
      div ~a:(a_class ["comment-user"]  :: []) [
        div ~a:[a_class ["comment-avatar"]]
        [img ~src:avatar ~alt:(Printf.sprintf "Avatar image for user %s" display_name)
          ~a:[a_class ["comment-avatar-img"]] ()];
        a ~a:(a_class ["comment-name"] :: url)
          [ txt display_name ];
      ]
    )

(** converts a ActivityPub comment into a HTML representation *)
let descendent_to_html_opt (desc: Yojson.Basic.t) =
  let format_js_date (txt: string) =
    let date = new%js Js.date_fromTimeValue (Js.date##parse (Js.string txt)) in
    let year = date##getUTCFullYear in
    let month = match date##getUTCMonth with
      | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr" | 5 -> "May" | 6 -> "Jun"
      | 7 -> "Jul" | 8 -> "Aug" | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec" | _ -> ""
    in
    let day =
      let num = date##getUTCDay in
      let suffix = match num % 10 with
        | 0 | 4 | 5 | 6 | 7 | 8 | 9 -> "th" | 1 -> "st" | 2 -> "nd" | 3 -> "rd" | _ -> ""
      in Printf.sprintf "%d%s" num suffix in
    let time =
      let hours = date##getUTCHours in
      let minutes = date##getUTCMinutes in
      Printf.sprintf "%02d:%02d"  hours minutes in
    Printf.sprintf "%s, %s of %s, %d" time day month year in
  let open Yojson.Basic.Util in
  let (let+) x f = Option.bind x ~f in
  let+ account = member "account" desc |> account_to_html_opt in
  let+ text = member "content" desc |> to_string_option in
  let text = text |> Js.bytestring |> Js.unescape |> Js.decodeURI |> Js.to_bytestring in
  let+ date = member "created_at" desc |> to_string_option in
  let+ url = member "url" desc |> to_string_option in
  (* let tags = member "tags" desc |> to_list |> List.filter_map ~f:tag_to_html_opt in *)
  let+ id = member "id" desc |> to_string_option in
  let+ in_reply_to_id = member "in_reply_to_id" desc |> to_string_option in

  (* convert a string to tyxml *)
  let string_to_html txt =
    let div = Dom_html.createDiv Dom_html.window##.document in
    div##setAttribute (Js.string "class") (Js.string "comment-message");
    div##.innerHTML := (Js.string txt);
    T.Of_dom.of_div div in

  Option.return @@ (
    in_reply_to_id,
    (id,
     T.Html.(
       div ~a:[a_class ["comment"]] [
         account;
         div ~a:[a_class ["comment-content"]]
           [
             string_to_html text;
             div ~a:[a_class ["comment-date"]] [
               b [(txt "Posted on")]; txt (format_js_date date)
             ];
             div ~a:[a_class ["comment-reply"]] [
               a ~a:[a_class ["comment-url"]; a_href url] [txt "reply"];
               img
                 ~src:"https://upload.wikimedia.org/wikipedia/commons/9/95/Ic_reply_48px.svg"
                 ~alt:"reply icon" ()
             ]

           ]
       ]
     )
    )
  )
  
(** given a list of comments (in the form (parent, (id, content))), returns a list of nested comments *)
let nest_descendents root_id (descendents_html: (string * (string * [> Html_types.div ] T.Html.elt)) list) =
  let set map ~key ~data =
    List.Assoc.remove map ~equal:String.equal key
    |> (fun ls -> List.Assoc.add ls ~equal:String.equal key data) in
  let map = List.fold descendents_html ~init:[] ~f:(fun map (parent, (id, elem)) ->
      let map = set ~key:id ~data:(`Children (elem, [])) map in
      match List.Assoc.find ~equal:String.equal map parent with
      | None ->
        set map  ~key:parent ~data:(`Root ([id]))
      | Some `Children (elem, ids) ->
        set map ~key:parent ~data:(`Children (elem, id :: ids))
      | Some `Root ids ->
        set map ~key:parent ~data:(`Root (id :: ids))
    ) in
  let rec resolve id =
    match List.Assoc.find ~equal:String.equal map id with
    | None -> []
    | Some (`Root ids) -> List.concat_map (List.rev ids) ~f:resolve
    | Some (`Children (elem, children)) ->
      let children = List.concat_map (List.rev children) ~f:resolve in
      T.Html.(
        [div ~a:([a_class ["comments-nested"]]) @@
         elem :: children]
      )
  in
  resolve root_id  

(** parse and convert comments retrieved from Activitypub into a series of HTML comments. *)
let handle_retrieved_data root_id (json: Yojson.Basic.t) (insert_point: Dom.element Js.t) : unit =
  let open Yojson.Basic.Util in
  let descendents = member "descendants" json |> to_list in
  let descendents_html = List.filter_map descendents ~f:descendent_to_html_opt in
  let nested_descendents = nest_descendents root_id descendents_html in
  let contents =
    let root_url = Printf.sprintf "%s/notice/%s" instance_url root_id  in
    T.Html.(
      div ~a:[a_class ["comments-panel"]] @@
        nested_descendents @ [
        div ~a:[a_class ["post-reply"]] [
               a ~a:[a_class ["post-url"]; a_href root_url] [txt "reply"];
               img
                 ~src:reply_icon_url
                 ~alt:"reply icon" ()
             ]
      ]
    ) |> T.To_dom.of_node in
  Dom.appendChild insert_point contents

(** Load comments and insert into page. *)
let load_comments comment_id (insert_point: Dom.element Js.t) =
  let module Html = Dom_html in
  let (let+) x f = Lwt.bind x f in
  (* first, load the comments from external client *)
  let url =
    Printf.sprintf
      "%s/api/v1/statuses/%s/context"
      instance_url
      comment_id
  in
  let+ (response, body) = Client.get (Uri.of_string url) in
  let status = response.status in
  let err_code = Cohttp.Code.code_of_status status in
  match Cohttp.Code.is_success err_code with
  | true ->                      (* happy path we got a response *)
    let+ body_text = (Cohttp_lwt.Body.to_string body) in
    let json_body = Yojson.Basic.from_string body_text in
    handle_retrieved_data comment_id json_body insert_point;
    Lwt.return_unit
  | false ->              (* unhappy path, got some failure *)
    let error_response = 
      let reason = Cohttp.Code.reason_phrase_of_code err_code in
      let document =
        T.Html.(
          div
            ~a:[a_class ["comments-panel"; "comments-panel-error"]] [
            p [(txt "Could not load comments")] ;
            p [txt (Printf.sprintf "Reason: %s (%d)" reason err_code)]
          ]
        ) in
      T.To_dom.of_node document
    in    
    Dom.appendChild insert_point error_response;
    Lwt.return_unit

let start _ =
  let module Html = Dom_html in
  let start_internal comment_id insert_point  =
    Lwt.ignore_result @@ load_comments comment_id insert_point;
    Js._false in
  match Html.getElementById_opt base_comment_id with
  | None ->
    print_endline (Printf.sprintf "could not find base element (expecting element with id #%s)" base_comment_id);
    Js._false
  | Some comments_element ->
    let comment_id = Js.to_string comments_element##.innerHTML in
    comments_element##.innerHTML := Js.string "";
    let element = Dom.CoerceTo.element comments_element |> Js.Opt.to_option in
    match element with
    | None -> print_endline "could not coerce to element"; Js._false
    | Some element ->
      start_internal comment_id element

let _ =
  let module Html = Dom_html in
  Html.window##.onload := Html.handler (start)
