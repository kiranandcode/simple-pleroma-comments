# Pleroma Comments
*Privacy respecting FOSS comments system for static webpages.*

![pleroma-comments-example-image](https://github.com/Gopiandcode/pleroma-comments/raw/master/example.png)

Having comments can be a great way to spice up a blog or personal
site, however most popular solutions for online comments (looking at
you Disqus) are proprietary non-free privacy-disrespecting ~~pieces of
trash~~ *ahem* software.

## Dependencies
I *hate* Javascript and refuse to write a single line of that godforsaken language.

As such, this plugin is actually built by transpiling from `Ocaml`.

To build the plugin, you'll need the following dependencies:
`
core_kernel
base
js_of_ocaml-tyxml
js_of_ocaml
js_of_ocaml-lwt
cohttp
cohttp-lwt-jsoo
lwt
yojson
`
All of these can be installed from opam using `opam install <package-name>`.

## Building
To build the plugin:

1. open the `pleroma_comments.ml` file and edit:
  - `instance_url` - to your home pleroma instance (default: "https://mastadon.social.com")
  - `base_comment_id` - the id of the element that pleroma-comments will as the insertion point  (default: "comments")
  - `reply_icon_url` - icon of reply 

2. run `opam build ./pleroma_comments.js`

3. exported javascript can be found at `./_build/default/pleroma_comment.js`

4. (optional) open `./_build/default/index.html` to test whether the package works (you may need to modify the comment id).

## Usage
The idea of this plugin builds on the idea presented in this
[blog-post](https://ecmelberk.com/fediverse-comments.html) by Ecmel
Berk Canlıer.

When you want to support comments for a blog or page, first share the
page on the fediverse in dedicated post. Pleroma-comments will then
read any responses to this post and pretty print them on the base html
page. 

Assuming you've made a post on the Fediverse, and have since found your post's id.

Simply add the script to your server (also update your [JS-licences](https://www.gnu.org/licenses/javascript-labels.html) to mention it's FOSS), and load the script in the head of your page:
```
<script type="text/javascript" src="pleroma_comments.js"></script>
```

When you want comments, place a div into your static page - the only contents of the div should be the ID of your post.
```
<div id="comments">9x4Lf0vc7HBztCRDfM</div>
```

On loading the page, pleroma-comments will replace this element with html representing the comments:
```
<div class="comments-panel">
   <div class="comments-nested">
      <div class="comment">
         <div class="comment-user">
            <div class="comment-avatar"><img src="..."></div>
            <a class="comment-name" href="<pleroma-instance>/users/gopiandcode">Kiran Gopinathan</a>
         </div>
         <div class="comment-content">
            <div class="comment-message">Response to first post.</div>
            <div class="comment-date"><b>Posted on</b>07:44, 2nd of Jun, 2020</div>
            <div class="comment-reply">
               <a class="comment-url" href="<pleroma-instance>/notice/<id>">reply</a><img src="...">
            </div>
         </div>
      </div>
      <div class="comments-nested">
         <div class="comment">
            <div class="comment-user">
               <div class="comment-avatar"><img src="..."></div>
                  <a class="comment-name" href="<pleroma-instance>/users/gopiandcode">Kiran Gopinathan</a>
            </div>
            <div class="comment-content">
               <div class="comment-message">Nested response to response to first post. 
                    <a class="hashtag" data-tag="tagged" href="<pleroma-instance>/tag/tagged">#tagged</a>
               </div>
               <div class="comment-date"><b>Posted on</b>13:10, 2nd of Jun, 2020</div>
               <div class="comment-reply"><a class="comment-url" href="<pleroma-instance>/notice/9x4s0116BCPGmJ3slk">reply</a><img src="..."></div>
            </div>
         </div>
      </div>
   </div>
   <div class="post-reply">
   <a class="post-url" href="<pleroma-instance>/notice/9x4Lf0vc7HBztCRDfM">reply</a>
   <img src="...">
   </div>
</div>
```
Style as you need.
