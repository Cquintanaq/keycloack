<#macro kw invalid name autofocus=false disabled=false message=true required=true rest...>
  <label class="sr-only" for="${name}">
    <#nested>
  </label>
  <input
    <#if autofocus>autofocus</#if>
    <#if disabled>disabled</#if>
    <#if required>required</#if>
    aria-invalid="${messagesPerField.existsError(invalid)?c}"
    class="input-reset"
    id="${name}"
    name="${name}"
    placeholder="<#compress><#nested></#compress>"
    <#list rest as attrName, attrValue>
      ${attrName}="${attrValue}"
    </#list>
  >
  <#if message && messagesPerField.existsError(invalid)>
    <div class="mt-2 text-red-600 text-sm">
      ${kcSanitize(messagesPerField.getFirstError(invalid))?no_esc}
    </div>
  </#if>
</#macro>
