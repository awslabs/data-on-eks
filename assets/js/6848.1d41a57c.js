"use strict";(self.webpackChunkdoeks_website=self.webpackChunkdoeks_website||[]).push([["6848"],{83837:function(t,e,i){i.d(e,{AD:()=>u,AE:()=>o,Mu:()=>s,O:()=>a,kc:()=>h,rB:()=>c,yU:()=>l});var n=i(134),r=i(17967),s=(0,n.eW)((t,e)=>{let i=t.append("rect");if(i.attr("x",e.x),i.attr("y",e.y),i.attr("fill",e.fill),i.attr("stroke",e.stroke),i.attr("width",e.width),i.attr("height",e.height),e.name&&i.attr("name",e.name),e.rx&&i.attr("rx",e.rx),e.ry&&i.attr("ry",e.ry),void 0!==e.attrs)for(let t in e.attrs)i.attr(t,e.attrs[t]);return e.class&&i.attr("class",e.class),i},"drawRect"),a=(0,n.eW)((t,e)=>{s(t,{x:e.startx,y:e.starty,width:e.stopx-e.startx,height:e.stopy-e.starty,fill:e.fill,stroke:e.stroke,class:"rect"}).lower()},"drawBackgroundRect"),l=(0,n.eW)((t,e)=>{let i=e.text.replace(n.Vw," "),r=t.append("text");r.attr("x",e.x),r.attr("y",e.y),r.attr("class","legend"),r.style("text-anchor",e.anchor),e.class&&r.attr("class",e.class);let s=r.append("tspan");return s.attr("x",e.x+2*e.textMargin),s.text(i),r},"drawText"),o=(0,n.eW)((t,e,i,n)=>{let s=t.append("image");s.attr("x",e),s.attr("y",i);let a=(0,r.sanitizeUrl)(n);s.attr("xlink:href",a)},"drawImage"),c=(0,n.eW)((t,e,i,n)=>{let s=t.append("use");s.attr("x",e),s.attr("y",i);let a=(0,r.sanitizeUrl)(n);s.attr("xlink:href",`#${a}`)},"drawEmbeddedImage"),h=(0,n.eW)(()=>({x:0,y:0,width:100,height:100,fill:"#EDF2AE",stroke:"#666",anchor:"start",rx:0,ry:0}),"getNoteRect"),u=(0,n.eW)(()=>({x:0,y:0,width:100,height:100,"text-anchor":"start",style:"#666",textMargin:0,rx:0,ry:0,tspan:!0}),"getTextObj")},64700:function(t,e,i){i.d(e,{G:()=>n});var n=(0,i(134).eW)(()=>`
  /* Font Awesome icon styling - consolidated */
  .label-icon {
    display: inline-block;
    height: 1em;
    overflow: visible;
    vertical-align: -0.125em;
  }
  
  .node .label-icon path {
    fill: currentColor;
    stroke: revert;
    stroke-width: revert;
  }
`,"getIconStyles")},36820:function(t,e,i){i.d(e,{diagram:()=>Y});var n=i(83837),r=i(64700),s=i(134),a=i(75910),l=function(){var t=(0,s.eW)(function(t,e,i,n){for(i=i||{},n=t.length;n--;i[t[n]]=e);return i},"o"),e=[6,8,10,11,12,14,16,17,18],i=[1,9],n=[1,10],r=[1,11],a=[1,12],l=[1,13],o=[1,14],c={trace:(0,s.eW)(function(){},"trace"),yy:{},symbols_:{error:2,start:3,journey:4,document:5,EOF:6,line:7,SPACE:8,statement:9,NEWLINE:10,title:11,acc_title:12,acc_title_value:13,acc_descr:14,acc_descr_value:15,acc_descr_multiline_value:16,section:17,taskName:18,taskData:19,$accept:0,$end:1},terminals_:{2:"error",4:"journey",6:"EOF",8:"SPACE",10:"NEWLINE",11:"title",12:"acc_title",13:"acc_title_value",14:"acc_descr",15:"acc_descr_value",16:"acc_descr_multiline_value",17:"section",18:"taskName",19:"taskData"},productions_:[0,[3,3],[5,0],[5,2],[7,2],[7,1],[7,1],[7,1],[9,1],[9,2],[9,2],[9,1],[9,1],[9,2]],performAction:(0,s.eW)(function(t,e,i,n,r,s,a){var l=s.length-1;switch(r){case 1:return s[l-1];case 2:case 6:case 7:this.$=[];break;case 3:s[l-1].push(s[l]),this.$=s[l-1];break;case 4:case 5:this.$=s[l];break;case 8:n.setDiagramTitle(s[l].substr(6)),this.$=s[l].substr(6);break;case 9:this.$=s[l].trim(),n.setAccTitle(this.$);break;case 10:case 11:this.$=s[l].trim(),n.setAccDescription(this.$);break;case 12:n.addSection(s[l].substr(8)),this.$=s[l].substr(8);break;case 13:n.addTask(s[l-1],s[l]),this.$="task"}},"anonymous"),table:[{3:1,4:[1,2]},{1:[3]},t(e,[2,2],{5:3}),{6:[1,4],7:5,8:[1,6],9:7,10:[1,8],11:i,12:n,14:r,16:a,17:l,18:o},t(e,[2,7],{1:[2,1]}),t(e,[2,3]),{9:15,11:i,12:n,14:r,16:a,17:l,18:o},t(e,[2,5]),t(e,[2,6]),t(e,[2,8]),{13:[1,16]},{15:[1,17]},t(e,[2,11]),t(e,[2,12]),{19:[1,18]},t(e,[2,4]),t(e,[2,9]),t(e,[2,10]),t(e,[2,13])],defaultActions:{},parseError:(0,s.eW)(function(t,e){if(e.recoverable)this.trace(t);else{var i=Error(t);throw i.hash=e,i}},"parseError"),parse:(0,s.eW)(function(t){var e=this,i=[0],n=[],r=[null],a=[],l=this.table,o="",c=0,h=0,u=0,p=a.slice.call(arguments,1),y=Object.create(this.lexer),d={};for(var f in this.yy)Object.prototype.hasOwnProperty.call(this.yy,f)&&(d[f]=this.yy[f]);y.setInput(t,d),d.lexer=y,d.parser=this,void 0===y.yylloc&&(y.yylloc={});var g=y.yylloc;a.push(g);var x=y.options&&y.options.ranges;function m(){var t;return"number"!=typeof(t=n.pop()||y.lex()||1)&&(t instanceof Array&&(t=(n=t).pop()),t=e.symbols_[t]||t),t}"function"==typeof d.parseError?this.parseError=d.parseError:this.parseError=Object.getPrototypeOf(this).parseError,(0,s.eW)(function(t){i.length=i.length-2*t,r.length=r.length-t,a.length=a.length-t},"popStack"),(0,s.eW)(m,"lex");for(var k,_,b,v,W,w,$,M,T,E={};;){if(b=i[i.length-1],this.defaultActions[b]?v=this.defaultActions[b]:(null==k&&(k=m()),v=l[b]&&l[b][k]),void 0===v||!v.length||!v[0]){var S="";for(w in T=[],l[b])this.terminals_[w]&&w>2&&T.push("'"+this.terminals_[w]+"'");S=y.showPosition?"Parse error on line "+(c+1)+":\n"+y.showPosition()+"\nExpecting "+T.join(", ")+", got '"+(this.terminals_[k]||k)+"'":"Parse error on line "+(c+1)+": Unexpected "+(1==k?"end of input":"'"+(this.terminals_[k]||k)+"'"),this.parseError(S,{text:y.match,token:this.terminals_[k]||k,line:y.yylineno,loc:g,expected:T})}if(v[0]instanceof Array&&v.length>1)throw Error("Parse Error: multiple actions possible at state: "+b+", token: "+k);switch(v[0]){case 1:i.push(k),r.push(y.yytext),a.push(y.yylloc),i.push(v[1]),k=null,_?(k=_,_=null):(h=y.yyleng,o=y.yytext,c=y.yylineno,g=y.yylloc,u>0&&u--);break;case 2:if($=this.productions_[v[1]][1],E.$=r[r.length-$],E._$={first_line:a[a.length-($||1)].first_line,last_line:a[a.length-1].last_line,first_column:a[a.length-($||1)].first_column,last_column:a[a.length-1].last_column},x&&(E._$.range=[a[a.length-($||1)].range[0],a[a.length-1].range[1]]),void 0!==(W=this.performAction.apply(E,[o,h,c,d,v[1],r,a].concat(p))))return W;$&&(i=i.slice(0,-1*$*2),r=r.slice(0,-1*$),a=a.slice(0,-1*$)),i.push(this.productions_[v[1]][0]),r.push(E.$),a.push(E._$),M=l[i[i.length-2]][i[i.length-1]],i.push(M);break;case 3:return!0}}return!0},"parse")};function h(){this.yy={}}return c.lexer={EOF:1,parseError:(0,s.eW)(function(t,e){if(this.yy.parser)this.yy.parser.parseError(t,e);else throw Error(t)},"parseError"),setInput:(0,s.eW)(function(t,e){return this.yy=e||this.yy||{},this._input=t,this._more=this._backtrack=this.done=!1,this.yylineno=this.yyleng=0,this.yytext=this.matched=this.match="",this.conditionStack=["INITIAL"],this.yylloc={first_line:1,first_column:0,last_line:1,last_column:0},this.options.ranges&&(this.yylloc.range=[0,0]),this.offset=0,this},"setInput"),input:(0,s.eW)(function(){var t=this._input[0];return this.yytext+=t,this.yyleng++,this.offset++,this.match+=t,this.matched+=t,t.match(/(?:\r\n?|\n).*/g)?(this.yylineno++,this.yylloc.last_line++):this.yylloc.last_column++,this.options.ranges&&this.yylloc.range[1]++,this._input=this._input.slice(1),t},"input"),unput:(0,s.eW)(function(t){var e=t.length,i=t.split(/(?:\r\n?|\n)/g);this._input=t+this._input,this.yytext=this.yytext.substr(0,this.yytext.length-e),this.offset-=e;var n=this.match.split(/(?:\r\n?|\n)/g);this.match=this.match.substr(0,this.match.length-1),this.matched=this.matched.substr(0,this.matched.length-1),i.length-1&&(this.yylineno-=i.length-1);var r=this.yylloc.range;return this.yylloc={first_line:this.yylloc.first_line,last_line:this.yylineno+1,first_column:this.yylloc.first_column,last_column:i?(i.length===n.length?this.yylloc.first_column:0)+n[n.length-i.length].length-i[0].length:this.yylloc.first_column-e},this.options.ranges&&(this.yylloc.range=[r[0],r[0]+this.yyleng-e]),this.yyleng=this.yytext.length,this},"unput"),more:(0,s.eW)(function(){return this._more=!0,this},"more"),reject:(0,s.eW)(function(){return this.options.backtrack_lexer?(this._backtrack=!0,this):this.parseError("Lexical error on line "+(this.yylineno+1)+". You can only invoke reject() in the lexer when the lexer is of the backtracking persuasion (options.backtrack_lexer = true).\n"+this.showPosition(),{text:"",token:null,line:this.yylineno})},"reject"),less:(0,s.eW)(function(t){this.unput(this.match.slice(t))},"less"),pastInput:(0,s.eW)(function(){var t=this.matched.substr(0,this.matched.length-this.match.length);return(t.length>20?"...":"")+t.substr(-20).replace(/\n/g,"")},"pastInput"),upcomingInput:(0,s.eW)(function(){var t=this.match;return t.length<20&&(t+=this._input.substr(0,20-t.length)),(t.substr(0,20)+(t.length>20?"...":"")).replace(/\n/g,"")},"upcomingInput"),showPosition:(0,s.eW)(function(){var t=this.pastInput(),e=Array(t.length+1).join("-");return t+this.upcomingInput()+"\n"+e+"^"},"showPosition"),test_match:(0,s.eW)(function(t,e){var i,n,r;if(this.options.backtrack_lexer&&(r={yylineno:this.yylineno,yylloc:{first_line:this.yylloc.first_line,last_line:this.last_line,first_column:this.yylloc.first_column,last_column:this.yylloc.last_column},yytext:this.yytext,match:this.match,matches:this.matches,matched:this.matched,yyleng:this.yyleng,offset:this.offset,_more:this._more,_input:this._input,yy:this.yy,conditionStack:this.conditionStack.slice(0),done:this.done},this.options.ranges&&(r.yylloc.range=this.yylloc.range.slice(0))),(n=t[0].match(/(?:\r\n?|\n).*/g))&&(this.yylineno+=n.length),this.yylloc={first_line:this.yylloc.last_line,last_line:this.yylineno+1,first_column:this.yylloc.last_column,last_column:n?n[n.length-1].length-n[n.length-1].match(/\r?\n?/)[0].length:this.yylloc.last_column+t[0].length},this.yytext+=t[0],this.match+=t[0],this.matches=t,this.yyleng=this.yytext.length,this.options.ranges&&(this.yylloc.range=[this.offset,this.offset+=this.yyleng]),this._more=!1,this._backtrack=!1,this._input=this._input.slice(t[0].length),this.matched+=t[0],i=this.performAction.call(this,this.yy,this,e,this.conditionStack[this.conditionStack.length-1]),this.done&&this._input&&(this.done=!1),i)return i;if(this._backtrack)for(var s in r)this[s]=r[s];return!1},"test_match"),next:(0,s.eW)(function(){if(this.done)return this.EOF;this._input||(this.done=!0),this._more||(this.yytext="",this.match="");for(var t,e,i,n,r=this._currentRules(),s=0;s<r.length;s++)if((i=this._input.match(this.rules[r[s]]))&&(!e||i[0].length>e[0].length)){if(e=i,n=s,this.options.backtrack_lexer){if(!1!==(t=this.test_match(i,r[s])))return t;if(!this._backtrack)return!1;e=!1;continue}if(!this.options.flex)break}return e?!1!==(t=this.test_match(e,r[n]))&&t:""===this._input?this.EOF:this.parseError("Lexical error on line "+(this.yylineno+1)+". Unrecognized text.\n"+this.showPosition(),{text:"",token:null,line:this.yylineno})},"next"),lex:(0,s.eW)(function(){var t=this.next();return t||this.lex()},"lex"),begin:(0,s.eW)(function(t){this.conditionStack.push(t)},"begin"),popState:(0,s.eW)(function(){return this.conditionStack.length-1>0?this.conditionStack.pop():this.conditionStack[0]},"popState"),_currentRules:(0,s.eW)(function(){return this.conditionStack.length&&this.conditionStack[this.conditionStack.length-1]?this.conditions[this.conditionStack[this.conditionStack.length-1]].rules:this.conditions.INITIAL.rules},"_currentRules"),topState:(0,s.eW)(function(t){return(t=this.conditionStack.length-1-Math.abs(t||0))>=0?this.conditionStack[t]:"INITIAL"},"topState"),pushState:(0,s.eW)(function(t){this.begin(t)},"pushState"),stateStackSize:(0,s.eW)(function(){return this.conditionStack.length},"stateStackSize"),options:{"case-insensitive":!0},performAction:(0,s.eW)(function(t,e,i,n){switch(i){case 0:case 1:case 3:case 4:break;case 2:return 10;case 5:return 4;case 6:return 11;case 7:return this.begin("acc_title"),12;case 8:return this.popState(),"acc_title_value";case 9:return this.begin("acc_descr"),14;case 10:return this.popState(),"acc_descr_value";case 11:this.begin("acc_descr_multiline");break;case 12:this.popState();break;case 13:return"acc_descr_multiline_value";case 14:return 17;case 15:return 18;case 16:return 19;case 17:return":";case 18:return 6;case 19:return"INVALID"}},"anonymous"),rules:[/^(?:%(?!\{)[^\n]*)/i,/^(?:[^\}]%%[^\n]*)/i,/^(?:[\n]+)/i,/^(?:\s+)/i,/^(?:#[^\n]*)/i,/^(?:journey\b)/i,/^(?:title\s[^#\n;]+)/i,/^(?:accTitle\s*:\s*)/i,/^(?:(?!\n||)*[^\n]*)/i,/^(?:accDescr\s*:\s*)/i,/^(?:(?!\n||)*[^\n]*)/i,/^(?:accDescr\s*\{\s*)/i,/^(?:[\}])/i,/^(?:[^\}]*)/i,/^(?:section\s[^#:\n;]+)/i,/^(?:[^#:\n;]+)/i,/^(?::[^#\n;]+)/i,/^(?::)/i,/^(?:$)/i,/^(?:.)/i],conditions:{acc_descr_multiline:{rules:[12,13],inclusive:!1},acc_descr:{rules:[10],inclusive:!1},acc_title:{rules:[8],inclusive:!1},INITIAL:{rules:[0,1,2,3,4,5,6,7,9,11,14,15,16,17,18,19],inclusive:!0}}},(0,s.eW)(h,"Parser"),h.prototype=c,c.Parser=h,new h}();l.parser=l;var o="",c=[],h=[],u=[],p=(0,s.eW)(function(){c.length=0,h.length=0,o="",u.length=0,(0,s.ZH)()},"clear"),y=(0,s.eW)(function(t){o=t,c.push(t)},"addSection"),d=(0,s.eW)(function(){return c},"getSections"),f=(0,s.eW)(function(){let t=k(),e=0;for(;!t&&e<100;)t=k(),e++;return h.push(...u),h},"getTasks"),g=(0,s.eW)(function(){let t=[];return h.forEach(e=>{e.people&&t.push(...e.people)}),[...new Set(t)].sort()},"updateActors"),x=(0,s.eW)(function(t,e){let i=e.substr(1).split(":"),n=0,r=[];1===i.length?(n=Number(i[0]),r=[]):(n=Number(i[0]),r=i[1].split(","));let s=r.map(t=>t.trim()),a={section:o,type:o,people:s,task:t,score:n};u.push(a)},"addTask"),m=(0,s.eW)(function(t){let e={section:o,type:o,description:t,task:t,classes:[]};h.push(e)},"addTaskOrg"),k=(0,s.eW)(function(){let t=(0,s.eW)(function(t){return u[t].processed},"compileTask"),e=!0;for(let[i,n]of u.entries())t(i),e=e&&n.processed;return e},"compileTasks"),_=(0,s.eW)(function(){return g()},"getActors"),b={getConfig:(0,s.eW)(()=>(0,s.nV)().journey,"getConfig"),clear:p,setDiagramTitle:s.g2,getDiagramTitle:s.Kr,setAccTitle:s.GN,getAccTitle:s.eu,setAccDescription:s.U$,getAccDescription:s.Mx,addSection:y,getSections:d,getTasks:f,addTask:x,addTaskOrg:m,getActors:_},v=(0,s.eW)(t=>`.label {
    font-family: ${t.fontFamily};
    color: ${t.textColor};
  }
  .mouth {
    stroke: #666;
  }

  line {
    stroke: ${t.textColor}
  }

  .legend {
    fill: ${t.textColor};
    font-family: ${t.fontFamily};
  }

  .label text {
    fill: #333;
  }
  .label {
    color: ${t.textColor}
  }

  .face {
    ${t.faceColor?`fill: ${t.faceColor}`:"fill: #FFF8DC"};
    stroke: #999;
  }

  .node rect,
  .node circle,
  .node ellipse,
  .node polygon,
  .node path {
    fill: ${t.mainBkg};
    stroke: ${t.nodeBorder};
    stroke-width: 1px;
  }

  .node .label {
    text-align: center;
  }
  .node.clickable {
    cursor: pointer;
  }

  .arrowheadPath {
    fill: ${t.arrowheadColor};
  }

  .edgePath .path {
    stroke: ${t.lineColor};
    stroke-width: 1.5px;
  }

  .flowchart-link {
    stroke: ${t.lineColor};
    fill: none;
  }

  .edgeLabel {
    background-color: ${t.edgeLabelBackground};
    rect {
      opacity: 0.5;
    }
    text-align: center;
  }

  .cluster rect {
  }

  .cluster text {
    fill: ${t.titleColor};
  }

  div.mermaidTooltip {
    position: absolute;
    text-align: center;
    max-width: 200px;
    padding: 2px;
    font-family: ${t.fontFamily};
    font-size: 12px;
    background: ${t.tertiaryColor};
    border: 1px solid ${t.border2};
    border-radius: 2px;
    pointer-events: none;
    z-index: 100;
  }

  .task-type-0, .section-type-0  {
    ${t.fillType0?`fill: ${t.fillType0}`:""};
  }
  .task-type-1, .section-type-1  {
    ${t.fillType0?`fill: ${t.fillType1}`:""};
  }
  .task-type-2, .section-type-2  {
    ${t.fillType0?`fill: ${t.fillType2}`:""};
  }
  .task-type-3, .section-type-3  {
    ${t.fillType0?`fill: ${t.fillType3}`:""};
  }
  .task-type-4, .section-type-4  {
    ${t.fillType0?`fill: ${t.fillType4}`:""};
  }
  .task-type-5, .section-type-5  {
    ${t.fillType0?`fill: ${t.fillType5}`:""};
  }
  .task-type-6, .section-type-6  {
    ${t.fillType0?`fill: ${t.fillType6}`:""};
  }
  .task-type-7, .section-type-7  {
    ${t.fillType0?`fill: ${t.fillType7}`:""};
  }

  .actor-0 {
    ${t.actor0?`fill: ${t.actor0}`:""};
  }
  .actor-1 {
    ${t.actor1?`fill: ${t.actor1}`:""};
  }
  .actor-2 {
    ${t.actor2?`fill: ${t.actor2}`:""};
  }
  .actor-3 {
    ${t.actor3?`fill: ${t.actor3}`:""};
  }
  .actor-4 {
    ${t.actor4?`fill: ${t.actor4}`:""};
  }
  .actor-5 {
    ${t.actor5?`fill: ${t.actor5}`:""};
  }
  ${(0,r.G)()}
`,"getStyles"),W=(0,s.eW)(function(t,e){return(0,n.Mu)(t,e)},"drawRect"),w=(0,s.eW)(function(t,e){let i=t.append("circle").attr("cx",e.cx).attr("cy",e.cy).attr("class","face").attr("r",15).attr("stroke-width",2).attr("overflow","visible"),n=t.append("g");function r(t){let i=(0,a.Nb1)().startAngle(Math.PI/2).endAngle(Math.PI/2*3).innerRadius(7.5).outerRadius(15/2.2);t.append("path").attr("class","mouth").attr("d",i).attr("transform","translate("+e.cx+","+(e.cy+2)+")")}function l(t){let i=(0,a.Nb1)().startAngle(3*Math.PI/2).endAngle(Math.PI/2*5).innerRadius(7.5).outerRadius(15/2.2);t.append("path").attr("class","mouth").attr("d",i).attr("transform","translate("+e.cx+","+(e.cy+7)+")")}function o(t){t.append("line").attr("class","mouth").attr("stroke",2).attr("x1",e.cx-5).attr("y1",e.cy+7).attr("x2",e.cx+5).attr("y2",e.cy+7).attr("class","mouth").attr("stroke-width","1px").attr("stroke","#666")}return n.append("circle").attr("cx",e.cx-5).attr("cy",e.cy-5).attr("r",1.5).attr("stroke-width",2).attr("fill","#666").attr("stroke","#666"),n.append("circle").attr("cx",e.cx+5).attr("cy",e.cy-5).attr("r",1.5).attr("stroke-width",2).attr("fill","#666").attr("stroke","#666"),(0,s.eW)(r,"smile"),(0,s.eW)(l,"sad"),(0,s.eW)(o,"ambivalent"),e.score>3?r(n):e.score<3?l(n):o(n),i},"drawFace"),$=(0,s.eW)(function(t,e){let i=t.append("circle");return i.attr("cx",e.cx),i.attr("cy",e.cy),i.attr("class","actor-"+e.pos),i.attr("fill",e.fill),i.attr("stroke",e.stroke),i.attr("r",e.r),void 0!==i.class&&i.attr("class",i.class),void 0!==e.title&&i.append("title").text(e.title),i},"drawCircle"),M=(0,s.eW)(function(t,e){return(0,n.yU)(t,e)},"drawText"),T=(0,s.eW)(function(t,e,i){let r=t.append("g"),s=(0,n.kc)();s.x=e.x,s.y=e.y,s.fill=e.fill,s.width=i.width*e.taskCount+i.diagramMarginX*(e.taskCount-1),s.height=i.height,s.class="journey-section section-type-"+e.num,s.rx=3,s.ry=3,W(r,s),A(i)(e.text,r,s.x,s.y,s.width,s.height,{class:"journey-section section-type-"+e.num},i,e.colour)},"drawSection"),E=-1,S=(0,s.eW)(function(t,e,i){let r=e.x+i.width/2,s=t.append("g");E++,s.append("line").attr("id","task"+E).attr("x1",r).attr("y1",e.y).attr("x2",r).attr("y2",450).attr("class","task-line").attr("stroke-width","1px").attr("stroke-dasharray","4 2").attr("stroke","#666"),w(s,{cx:r,cy:300+(5-e.score)*30,score:e.score});let a=(0,n.kc)();a.x=e.x,a.y=e.y,a.fill=e.fill,a.width=i.width,a.height=i.height,a.class="task task-type-"+e.num,a.rx=3,a.ry=3,W(s,a);let l=e.x+14;e.people.forEach(t=>{let i=e.actors[t].color;$(s,{cx:l,cy:e.y,r:7,fill:i,stroke:"#000",title:t,pos:e.actors[t].position}),l+=10}),A(i)(e.task,s,a.x,a.y,a.width,a.height,{class:"task"},i,e.colour)},"drawTask"),A=function(){function t(t,e,i,r,s,a,l,o){n(e.append("text").attr("x",i+s/2).attr("y",r+a/2+5).style("font-color",o).style("text-anchor","middle").text(t),l)}function e(t,e,i,r,s,a,l,o,c){let{taskFontSize:h,taskFontFamily:u}=o,p=t.split(/<br\s*\/?>/gi);for(let t=0;t<p.length;t++){let o=t*h-h*(p.length-1)/2,y=e.append("text").attr("x",i+s/2).attr("y",r).attr("fill",c).style("text-anchor","middle").style("font-size",h).style("font-family",u);y.append("tspan").attr("x",i+s/2).attr("dy",o).text(p[t]),y.attr("y",r+a/2).attr("dominant-baseline","central").attr("alignment-baseline","central"),n(y,l)}}function i(t,i,r,s,a,l,o,c){let h=i.append("switch"),u=h.append("foreignObject").attr("x",r).attr("y",s).attr("width",a).attr("height",l).attr("position","fixed").append("xhtml:div").style("display","table").style("height","100%").style("width","100%");u.append("div").attr("class","label").style("display","table-cell").style("text-align","center").style("vertical-align","middle").text(t),e(t,h,r,s,a,l,o,c),n(u,o)}function n(t,e){for(let i in e)i in e&&t.attr(i,e[i])}return(0,s.eW)(t,"byText"),(0,s.eW)(e,"byTspan"),(0,s.eW)(i,"byFo"),(0,s.eW)(n,"_setTextAttrs"),function(n){return"fo"===n.textPlacement?i:"old"===n.textPlacement?t:e}}(),C=(0,s.eW)(function(t){t.append("defs").append("marker").attr("id","arrowhead").attr("refX",5).attr("refY",2).attr("markerWidth",6).attr("markerHeight",4).attr("orient","auto").append("path").attr("d","M 0,0 V 4 L6,2 Z")},"initGraphics"),I=(0,s.eW)(function(t){Object.keys(t).forEach(function(e){F[e]=t[e]})},"setConf"),P={},j=0;function V(t){let e=(0,s.nV)().journey,i=e.maxLabelWidth;j=0;let n=60;Object.keys(P).forEach(r=>{let s=P[r].color;$(t,{cx:20,cy:n,r:7,fill:s,stroke:"#000",pos:P[r].position});let a=t.append("text").attr("visibility","hidden").text(r),l=a.node().getBoundingClientRect().width;a.remove();let o=[];if(l<=i)o=[r];else{let e=r.split(" "),n="";a=t.append("text").attr("visibility","hidden"),e.forEach(t=>{let e=n?`${n} ${t}`:t;if(a.text(e),a.node().getBoundingClientRect().width>i){if(n&&o.push(n),n=t,a.text(t),a.node().getBoundingClientRect().width>i){let e="";for(let n of t)e+=n,a.text(e+"-"),a.node().getBoundingClientRect().width>i&&(o.push(e.slice(0,-1)+"-"),e=n);n=e}}else n=e}),n&&o.push(n),a.remove()}o.forEach((i,r)=>{let s=M(t,{x:40,y:n+7+20*r,fill:"#666",text:i,textMargin:e.boxTextMargin??5}).node().getBoundingClientRect().width;s>j&&s>e.leftMargin-s&&(j=s)}),n+=Math.max(20,20*o.length)})}(0,s.eW)(V,"drawActorLegend");var F=(0,s.nV)().journey,B=0,N=(0,s.eW)(function(t,e,i,n){let r,l=(0,s.nV)(),o=l.journey.titleColor,c=l.journey.titleFontSize,h=l.journey.titleFontFamily,u=l.securityLevel;"sandbox"===u&&(r=(0,a.Ys)("#i"+e));let p="sandbox"===u?(0,a.Ys)(r.nodes()[0].contentDocument.body):(0,a.Ys)("body");O.init();let y=p.select("#"+e);C(y);let d=n.db.getTasks(),f=n.db.getDiagramTitle(),g=n.db.getActors();for(let t in P)delete P[t];let x=0;g.forEach(t=>{P[t]={color:F.actorColours[x%F.actorColours.length],position:x},x++}),V(y),B=F.leftMargin+j,O.insert(0,0,B,50*Object.keys(P).length),L(y,d,0);let m=O.getBounds();f&&y.append("text").text(f).attr("x",B).attr("font-size",c).attr("font-weight","bold").attr("y",25).attr("fill",o).attr("font-family",h);let k=m.stopy-m.starty+2*F.diagramMarginY,_=B+m.stopx+2*F.diagramMarginX;(0,s.v2)(y,k,_,F.useMaxWidth),y.append("line").attr("x1",B).attr("y1",4*F.height).attr("x2",_-B-4).attr("y2",4*F.height).attr("stroke-width",4).attr("stroke","black").attr("marker-end","url(#arrowhead)");let b=70*!!f;y.attr("viewBox",`${m.startx} -25 ${_} ${k+b}`),y.attr("preserveAspectRatio","xMinYMin meet"),y.attr("height",k+b+25)},"draw"),O={data:{startx:void 0,stopx:void 0,starty:void 0,stopy:void 0},verticalPos:0,sequenceItems:[],init:(0,s.eW)(function(){this.sequenceItems=[],this.data={startx:void 0,stopx:void 0,starty:void 0,stopy:void 0},this.verticalPos=0},"init"),updateVal:(0,s.eW)(function(t,e,i,n){void 0===t[e]?t[e]=i:t[e]=n(i,t[e])},"updateVal"),updateBounds:(0,s.eW)(function(t,e,i,n){let r=(0,s.nV)().journey,a=this,l=0;function o(o){return(0,s.eW)(function(s){l++;let c=a.sequenceItems.length-l+1;a.updateVal(s,"starty",e-c*r.boxMargin,Math.min),a.updateVal(s,"stopy",n+c*r.boxMargin,Math.max),a.updateVal(O.data,"startx",t-c*r.boxMargin,Math.min),a.updateVal(O.data,"stopx",i+c*r.boxMargin,Math.max),"activation"!==o&&(a.updateVal(s,"startx",t-c*r.boxMargin,Math.min),a.updateVal(s,"stopx",i+c*r.boxMargin,Math.max),a.updateVal(O.data,"starty",e-c*r.boxMargin,Math.min),a.updateVal(O.data,"stopy",n+c*r.boxMargin,Math.max))},"updateItemBounds")}(0,s.eW)(o,"updateFn"),this.sequenceItems.forEach(o())},"updateBounds"),insert:(0,s.eW)(function(t,e,i,n){let r=Math.min(t,i),s=Math.max(t,i),a=Math.min(e,n),l=Math.max(e,n);this.updateVal(O.data,"startx",r,Math.min),this.updateVal(O.data,"starty",a,Math.min),this.updateVal(O.data,"stopx",s,Math.max),this.updateVal(O.data,"stopy",l,Math.max),this.updateBounds(r,a,s,l)},"insert"),bumpVerticalPos:(0,s.eW)(function(t){this.verticalPos=this.verticalPos+t,this.data.stopy=this.verticalPos},"bumpVerticalPos"),getVerticalPos:(0,s.eW)(function(){return this.verticalPos},"getVerticalPos"),getBounds:(0,s.eW)(function(){return this.data},"getBounds")},R=F.sectionFills,D=F.sectionColours,L=(0,s.eW)(function(t,e,i){let n=(0,s.nV)().journey,r="",a=i+(2*n.height+n.diagramMarginY),l=0,o="#CCC",c="black",h=0;for(let[i,s]of e.entries()){if(r!==s.section){o=R[l%R.length],h=l%R.length,c=D[l%D.length];let a=0,u=s.section;for(let t=i;t<e.length;t++)if(e[t].section==u)a+=1;else break;T(t,{x:i*n.taskMargin+i*n.width+B,y:50,text:s.section,fill:o,num:h,colour:c,taskCount:a},n),r=s.section,l++}let u=s.people.reduce((t,e)=>(P[e]&&(t[e]=P[e]),t),{});s.x=i*n.taskMargin+i*n.width+B,s.y=a,s.width=n.diagramMarginX,s.height=n.diagramMarginY,s.colour=c,s.fill=o,s.num=h,s.actors=u,S(t,s,n),O.insert(s.x,s.y,s.x+s.width+n.taskMargin,450)}},"drawTasks"),z={setConf:I,draw:N},Y={parser:l,db:b,renderer:z,styles:v,init:(0,s.eW)(t=>{z.setConf(t.journey),b.clear()},"init")}}}]);